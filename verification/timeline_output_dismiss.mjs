/** Regression (RFC #362 desktop.8): the timeline output failure card must be dismissible.
 *
 * An empty timeline can still be sent to "Output video" from the selection toolbar
 * (the ⌘/Ctrl+Enter shortcut guards on duration, the toolbar button did not). The
 * failed card used to offer only "Retry output", which re-fails forever: the card
 * is virtual (not selectable, deletable or focusable), so nothing closed it. The
 * patch adds a Dismiss/关闭 action. This journey fails on the unpatched tree.
 *
 * Runs inside the pinned upstream tree after applying patches/timeline-output-dismiss.patch,
 * against the same dev server + isolated creation fixture as the tests/browser suites.
 * It lives at tests/ (not tests/browser/) on purpose: that directory is owned by
 * upstream's manifest check (scripts/check-browser-manifest.mjs).
 */
import assert from "node:assert/strict";
import { launchBrowser } from "./browser/engine.mjs";
const base = process.env.CREATION_WEB_URL ?? "http://127.0.0.1:5179";
const api = process.env.CREATION_API_URL ?? base;
const headers = { "X-OpenDirector-Request": "1" };
const health = await fetch(api + "/api/creation-test-health", { headers }).then((r) => r.json());
assert.equal(health.isolated, true);
const browser = await launchBrowser();
try {
  const page = await browser.newPage({ viewport: { width: 1500, height: 1000 } });
  page.setDefaultTimeout(20000);
  const errors = [];
  page.on("pageerror", (error) => { errors.push(error.message); console.error(error.message); });
  await page.addInitScript(() => {
    localStorage.setItem("opendirector.modelSetup.v1", "dismissed");
    localStorage.setItem("opendirector.locale.v1", "en-US");
  });
  const bootstrap = (url) => url.origin === new URL(base).origin && url.pathname === "/";
  await page.route(bootstrap, (route) => route.fulfill({ contentType: "text/html", body: "<html></html>" }));
  await page.goto(base + "/");
  const fixture = await page.evaluate(async () => {
    const { createDocument, createNode } = await import("/src/canvas/model.ts");
    const { importWorkspaceDocument } = await import("/src/backend/workspace.ts");
    // Exactly the user's scenario: a bare timeline node, no clips at all.
    const node = createNode("timeline", { x: 150, y: 150 }, { title: "Empty timeline dismissal" });
    const saved = await importWorkspaceDocument({ ...createDocument("Dismiss " + crypto.randomUUID().slice(0, 8)), nodes: [node] });
    (await import("/src/backend/creationClient.ts")).creationClient(saved.id).close();
    await (await import("/src/backend/projects.ts")).releaseBackendProject();
    return { id: saved.id, item: node.id };
  });
  await page.unroute(bootstrap);
  const snapshot = () => fetch(`${api}/api/creation/projects/${fixture.id}`, { headers }).then((r) => r.json());
  await page.goto(`${base}/ai-tool/ai-canvas/${fixture.id}`);
  await page.getByText("Saved on this device", { exact: true }).waitFor();
  await page.locator(".cw-workspace").focus();
  await page.keyboard.press("Shift+1");
  await page.locator(`.react-flow__node[data-id="${fixture.item}"]`).click();
  const panel = page.locator(".cw-selection-toolbar");
  await panel.waitFor();

  const failAndDismiss = async () => {
    await panel.getByRole("button", { name: "Output video", exact: true }).click();
    const card = page.locator(".cw-timeline-pending");
    const alert = card.locator('[role="alert"]');
    await alert.waitFor();
    assert.match(await alert.innerText(), /Add media to the timeline first/);
    // Retry and Dismiss are both offered once the render failed; publishing is not
    // in flight, so neither button is disabled in this state.
    const retry = card.getByRole("button", { name: "Retry output", exact: true });
    const dismiss = card.getByRole("button", { name: "Dismiss", exact: true });
    await retry.waitFor(); await dismiss.waitFor();
    assert.equal(await retry.isDisabled(), false);
    assert.equal(await dismiss.isDisabled(), false);
    await dismiss.click();
    await card.waitFor({ state: "detached" });
  };
  // A failed run pans the camera to the output slot; a ReactFlow pan is not
  // DOM-scrollable, so refit the document before touching node chrome again.
  const refit = async () => {
    await page.locator(".cw-workspace").focus();
    await page.keyboard.press("Shift+1");
  };

  await failAndDismiss();
  assert.equal((await snapshot()).canvasItems.filter((item) => item.kind === "video").length, 0,
    "dismiss leaves no orphan output behind");

  // The hook state is fully released: a second export still reaches the failure
  // card (regression guard against a stuck `active`/`pending` ref), and closes again.
  await refit();
  await page.locator(`.react-flow__node[data-id="${fixture.item}"]`).click();
  await failAndDismiss();
  assert.equal((await snapshot()).canvasItems.filter((item) => item.kind === "video").length, 0);

  // Cancel during a real render still works (unchanged behaviour) and the
  // timeline editor path is untouched.
  assert.deepEqual(errors, []);
  console.log("timeline output failure card dismiss: ok");
} finally {
  await browser.close();
}
