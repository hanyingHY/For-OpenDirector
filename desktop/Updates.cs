using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

// All native update controls live outside the WebView; the renderer cannot
// choose a feed, executable, path, version or installation arguments.
internal sealed class Updates : IDisposable {
    const string Pref = @"Software\OpenDirector\Desktop";
    readonly Form owner;
    readonly Action closeForInstall;
    readonly Action<string> log;
    readonly Action<Process> contain;
    readonly NotifyIcon icon = new NotifyIcon();
    readonly ContextMenuStrip menu = new ContextMenuStrip();
    readonly ToolStripMenuItem automatic = new ToolStripMenuItem("自动检查并下载 / Automatic updates");
    readonly ToolStripMenuItem check = new ToolStripMenuItem("检查更新 / Check now");
    readonly ToolStripMenuItem stop = new ToolStripMenuItem("取消检查或下载 / Cancel");
    readonly ToolStripMenuItem install = new ToolStripMenuItem("安装并重启 / Install and restart");
    readonly Timer timer = new Timer { Interval = 12 * 60 * 60 * 1000 };
    readonly string dir = AppDomain.CurrentDomain.BaseDirectory;
    Process worker;
    string ready;
    bool cancelled, disposed, busy;
    public bool Applying { get; private set; }

    public Updates(Form form, Action close, Action<string> write, Action<Process> ownWorker) {
        owner=form; closeForInstall=close; log=write; contain=ownWorker;
        using(var key=Registry.CurrentUser.OpenSubKey(Pref))
            automatic.Checked=key==null || !Equals(key.GetValue("AutoUpdate",1),0);
        automatic.CheckOnClick=true;
        automatic.Click+=(s,e)=>{
            try { using(var key=Registry.CurrentUser.CreateSubKey(Pref)) key.SetValue("AutoUpdate",automatic.Checked?1:0,RegistryValueKind.DWord); }
            catch(Exception ex) { automatic.Checked=!automatic.Checked; MessageBox.Show(owner,ex.Message,"OpenDirector"); return; }
            if(automatic.Checked) Check(false); else Cancel();
        };
        menu.Items.Add("OpenDirector  " + File.ReadAllText(Path.Combine(dir,"VERSION")).Trim()).Enabled=false;
        menu.Items.Add(automatic); menu.Items.Add(check); menu.Items.Add(stop); menu.Items.Add(install);
        check.Click+=(s,e)=>Check(true); stop.Click+=(s,e)=>Cancel(); install.Click+=(s,e)=>Install();
        icon.Icon=SystemIcons.Application; icon.Text="OpenDirector · 更新 / Updates"; icon.ContextMenuStrip=menu;
        icon.BalloonTipClicked+=(s,e)=>Install(); icon.Visible=true;
        timer.Tick+=(s,e)=>{if(automatic.Checked) Check(false);}; timer.Start();
        Refresh(); if(automatic.Checked) Check(false);
    }
    void Refresh() { check.Enabled=!busy; stop.Enabled=busy&&!Applying; automatic.Enabled=!Applying; install.Enabled=!busy&&ready!=null; }
    void Cancel() {
        if(!busy || Applying) return;
        cancelled=true;
        try { if(worker!=null && !worker.HasExited) worker.Kill(); } catch(InvalidOperationException) {}
    }
    async Task<string> Run(string arguments, bool download) {
        var info=new ProcessStartInfo(Path.Combine(dir,"python","python.exe"),"-I -X utf8 \""+Path.Combine(dir,"update.py")+"\""+arguments);
        info.WorkingDirectory=dir; info.UseShellExecute=false; info.CreateNoWindow=true;
        info.RedirectStandardOutput=true; info.RedirectStandardError=true;
        using(var p=new Process { StartInfo=info }) {
            p.Start(); worker=p;
            try {
                // Downloads die with the host. The confirmed handoff is deliberately
                // outside the service job so that the installer survives shutdown.
                if(download) contain(p);
                var output=p.StandardOutput.ReadToEndAsync(); var error=p.StandardError.ReadToEndAsync();
                await Task.Run((Action)p.WaitForExit);
                var text=(await output).Trim(); var detail=(await error).Trim();
                if(p.ExitCode!=0) throw new IOException(detail);
                return text;
            } finally { worker=null; if(!p.HasExited) p.Kill(); }
        }
    }
    void Problem(Exception e, bool notify) {
        log("Updater: " + e.Message);
        if(notify) MessageBox.Show(owner,"更新未完成，当前版本仍可使用。请检查网络和磁盘空间，再从托盘重试。\nUpdate not applied. Check network/free space and retry from the tray.\n\n"+e.Message,"OpenDirector");
    }
    async void Check(bool manual) {
        if(busy || disposed) return;
        busy=true; cancelled=false; ready=null; Refresh();
        try {
            string result=await Run("",true);
            if(disposed || cancelled) return;
            if(result=="NONE") {
                if(manual) MessageBox.Show(owner,"没有可用的稳定版更新。\nNo newer stable release is available.","OpenDirector");
            } else {
                if(!Regex.IsMatch(result,@"\A\d{1,6}\.\d{1,6}\.\d{1,6}-desktop\.\d{1,6}\z")) throw new IOException("Invalid updater response");
                ready=result;
                icon.ShowBalloonTip(10000,"OpenDirector " + ready,"新版已验证。准备好后从托盘安装。\nVerified update ready. Install from the tray.",ToolTipIcon.Info);
            }
        } catch(Exception ex) { if(!disposed && !cancelled) Problem(ex,manual); }
        finally { busy=false; if(!disposed) Refresh(); }
        if(manual && ready!=null && !disposed) Install();
    }
    async void Install() {
        if(busy || disposed || ready==null) return;
        if(MessageBox.Show(owner,"安装 " + ready + " 并重启？请先保存并等待导出及 Agent 任务结束，否则任务将被中断。\nInstall and restart? Save your work and finish exports and Agent tasks first. Running tasks will stop.","OpenDirector",MessageBoxButtons.YesNo,MessageBoxIcon.Question,MessageBoxDefaultButton.Button2)!=DialogResult.Yes) return;
        Applying=true; busy=true; Refresh();
        try {
            await Run(" --install "+ready+" "+Process.GetCurrentProcess().Id,false);
            closeForInstall();
        } catch(Exception e) { ready=null; Applying=false; busy=false; if(!disposed) { Refresh(); Problem(e,true); } }
    }
    public void Dispose() { disposed=true; Cancel(); timer.Dispose(); icon.Visible=false; icon.Dispose(); menu.Dispose(); }
}
