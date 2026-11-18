// Windows-only host for the upstream Chromium UI. No JavaScript/native bridge.
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Drawing;

using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Host {
    const string Origin = "http://127.0.0.1:48765";
    static readonly string Install = AppDomain.CurrentDomain.BaseDirectory;
    static readonly string State = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenDirector", "Desktop");
    static readonly string Log = Path.Combine(State, "desktop.log");
    static readonly object LogLock = new object();
    static readonly string Secret = NewSecret();
    static readonly TaskCompletionSource<bool> Ready = new TaskCompletionSource<bool>();
    static readonly string Ticket = Path.Combine(State,"session.bin");
    static Process service;
    static IntPtr job;
    static bool closing;
    static CoreWebView2Environment engine;
    static Form main;
    static string NewSecret() { var b = new byte[32]; using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(b); return Convert.ToBase64String(b); }
    static void Write(string s) { lock (LogLock) { try { File.AppendAllText(Log, DateTime.Now.ToString("s") + " " + s + Environment.NewLine); } catch (IOException) {} } }
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr handle, int info, IntPtr data, uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr handle, IntPtr proc);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static void StartService() {
        job = CreateJobObject(IntPtr.Zero, null);
        // x64 JOBOBJECT_EXTENDED_LIMIT_INFORMATION; kill the entire backend/Agent/
        // FFmpeg process tree if the UI crashes. Python blocks on stdin until assigned.
        byte[] limits = new byte[144]; BitConverter.GetBytes(0x2000).CopyTo(limits, 16);
        var h = GCHandle.Alloc(limits, GCHandleType.Pinned);
        try { if (job == IntPtr.Zero || !SetInformationJobObject(job, 9, h.AddrOfPinnedObject(), (uint)limits.Length)) throw new System.ComponentModel.Win32Exception(); }
        finally { h.Free(); }
        var info = new ProcessStartInfo(Path.Combine(Install, "python", "python.exe"), "-I -X utf8 -u \"" + Path.Combine(Install, "service.py") + "\"");
        info.WorkingDirectory = State; info.UseShellExecute = false; info.CreateNoWindow = true;
        info.RedirectStandardInput = info.RedirectStandardOutput = info.RedirectStandardError = true;
        info.EnvironmentVariables["PATH"] = Path.Combine(Install,"media") + ";" + Path.Combine(Install,"git","cmd") + ";" + info.EnvironmentVariables["PATH"];
        info.EnvironmentVariables["PYTHONUTF8"] = "1";
        info.EnvironmentVariables["OPENDIRECTOR_API_URL"] = Origin;
        service = new Process { StartInfo = info };
        service.ErrorDataReceived += (s,e) => { if(e.Data!=null) Write(e.Data); };
        service.OutputDataReceived += (s,e) => { if(e.Data=="OD-DESKTOP-READY") Ready.TrySetResult(true); else if(e.Data==null) Ready.TrySetResult(false); else Write(e.Data); };
        service.Start();
        if (!AssignProcessToJobObject(job, service.Handle)) { service.Kill(); throw new System.ComponentModel.Win32Exception(); }
        service.BeginErrorReadLine(); service.BeginOutputReadLine(); service.StandardInput.WriteLine(Secret); service.StandardInput.Flush();
    }
    static bool Local(string address) { Uri uri; return Uri.TryCreate(address,UriKind.Absolute,out uri) && uri.GetLeftPart(UriPartial.Authority) == Origin; }
    static Form Window() {
        return new Form { Text="OpenDirector", Width=1440, Height=900, MinimumSize=new Size(800,560), StartPosition=FormStartPosition.CenterScreen, BackColor=Color.FromArgb(24,24,24) };
    }
    static async Task Mount(Form form, string address) {
        var view = new WebView2 { Dock=DockStyle.Fill, DefaultBackgroundColor=Color.FromArgb(24,24,24) };
        form.Controls.Add(view); view.BringToFront();
        await view.EnsureCoreWebView2Async(engine);
        var core = view.CoreWebView2;
        core.Settings.AreHostObjectsAllowed=false; core.Settings.IsWebMessageEnabled=false;
        core.AddWebResourceRequestedFilter(Origin + "/*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (s,e) => { if(Local(e.Request.Uri)) e.Request.Headers.SetHeader("X-OpenDirector-Desktop",Secret); };
        core.NavigationStarting += (s,e) => { if (!Local(e.Uri)) e.Cancel=true; };
        core.FrameNavigationStarting += (s,e) => { if(!Local(e.Uri) && e.Uri!="about:blank" && !e.Uri.StartsWith("blob:"+Origin+"/",StringComparison.Ordinal)) e.Cancel=true; };
        core.NewWindowRequested += async (s,e) => {
            e.Handled=true; Uri uri; if(!Uri.TryCreate(e.Uri,UriKind.Absolute,out uri)) return;
            try {
                if(Local(e.Uri)) { var child=Window(); child.Show(form); await Mount(child,uri.AbsoluteUri); }
                else if(e.IsUserInitiated && uri.Scheme=="https") Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute=true });
            } catch(Exception ex) { Error(ex); }
        };
        core.ProcessFailed += (s,e) => { if(!closing && (e.ProcessFailedKind==CoreWebView2ProcessFailedKind.BrowserProcessExited || e.ProcessFailedKind==CoreWebView2ProcessFailedKind.RenderProcessExited)) Fail(new Exception("Rendering stopped. Restart the app. / 渲染已中断，请重启应用。")); };
        core.Navigate(address);
    }
    static void Error(Exception e) { Write(e.ToString()); MessageBox.Show(e.Message + "\n\nDiagnostics / 日志: " + Log,"OpenDirector", MessageBoxButtons.OK,MessageBoxIcon.Error); }
    static void Fail(Exception e) { if(closing) return; closing=true; Error(e); main.Close(); }
    [STAThread] public static void Main() {
        SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        bool first;
        using(var mutex = new Mutex(true,"Local\\OpenDirectorDesktop.x64",out first)) {
            if(!first) { MessageBox.Show("OpenDirector is already open. / 应用已打开。", "OpenDirector"); return; }
            try {
                Directory.CreateDirectory(State);
                if(File.Exists(Log) && new FileInfo(Log).Length>2000000) { File.Copy(Log,Log+".old",true); File.Delete(Log); }
                main=Window(); main.Controls.Add(new Label { Text="OpenDirector   ·   Starting / 正在启动…", ForeColor=Color.White, Dock=DockStyle.Fill, TextAlign=ContentAlignment.MiddleCenter });
                main.Shown += async (s,e) => { try {
                    StartService();
                    if(await Task.WhenAny(Ready.Task,Task.Delay(60000))!=Ready.Task || !await Ready.Task) throw new Exception("Local service did not start. Check port 48765 and the log. / 服务启动失败，请检查 48765 端口和日志。");
                    File.WriteAllBytes(Ticket, ProtectedData.Protect(System.Text.Encoding.ASCII.GetBytes(Secret),null,DataProtectionScope.CurrentUser));
                    service.Exited += (p,a) => { if(!closing && main.IsHandleCreated) main.BeginInvoke((Action)(() => Fail(new Exception("Service exited. Restart OpenDirector. / 服务已退出，请重启应用。")))); };
                    service.EnableRaisingEvents=true;
                    engine=await CoreWebView2Environment.CreateAsync(null, Path.Combine(State,"WebView2"));
                    await Mount(main,Origin+"/");
                } catch(WebView2RuntimeNotFoundException) { Fail(new Exception("Install Microsoft Edge WebView2 Evergreen Runtime (x64), then reopen. / 请安装微软 WebView2 Evergreen x64 运行时后重试。")); }
                  catch(Exception ex) { Fail(ex); } };
                main.FormClosing += (s,e) => {
                    if(!closing && e.CloseReason==CloseReason.UserClosing && MessageBox.Show(main,"Closing stops exports and running tasks. Close?\n关闭会中断导出和运行中的任务，确定关闭？","OpenDirector",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes) { e.Cancel=true; return; }
                    closing=true;
                };
                Application.Run(main);
            } catch(Exception e) { Error(e); }
            finally { closing=true; try { if(service!=null && !service.HasExited) { service.StandardInput.Close(); service.WaitForExit(5000); } } catch(InvalidOperationException) {} finally { if(job!=IntPtr.Zero) CloseHandle(job); try { File.Delete(Ticket); } catch(IOException) {} } }
        }
    }
}
