import { render } from "preact";
import { useEffect, useMemo, useState } from "preact/hooks";
import type { SyncChange, SyncReport } from "../../src/rules/payload.js";
import type { ScotchRegion, ScotchStyle, SpiritCategory } from "../../src/rules/enrich.js";
import * as api from "./api.js";
import {
  buildItems,
  CATEGORY_NAMES,
  formatNumber,
  houseFor,
  item as makeItem,
  matches,
  menuCategory,
  placement,
  REGION_NAMES,
  STYLE_NAMES,
  type Item,
  type Menu,
  type Override,
} from "./model.js";

// The admin console: sign in with the admin passcode, sync from
// CellarTracker, and browse and edit every bottle.

function App() {
  const [role, setRole] = useState<"loading" | "admin" | "guest" | null>("loading");
  useEffect(() => {
    api.currentRole().then(setRole, () => setRole(null));
  }, []);

  if (role === "loading") return <p class="center muted">Opening the cabinet…</p>;
  if (role !== "admin") return <SignIn onSignedIn={() => setRole("admin")} />;
  return <Admin onSignedOut={() => setRole(null)} />;
}

// MARK: Sign in

function SignIn({ onSignedIn }: { onSignedIn: () => void }) {
  const [passcode, setPasscode] = useState("");
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);

  async function submit(e: Event) {
    e.preventDefault();
    setBusy(true);
    setError(undefined);
    try {
      const role = await api.signIn(passcode);
      if (role === "admin") return onSignedIn();
      await api.signOut();
      setError("That's not the admin passcode.");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main class="signin">
      <div class="double-rule" />
      <h1>David's Cabinet</h1>
      <p class="caps">Admin</p>
      <div class="double-rule" />
      <form onSubmit={submit}>
        <label for="passcode">Admin passcode</label>
        <input
          id="passcode"
          type="password"
          autocomplete="current-password"
          value={passcode}
          onInput={(e) => setPasscode(e.currentTarget.value)}
          autofocus
        />
        <button class="primary" disabled={!passcode || busy}>
          {busy ? "Checking…" : "Sign in"}
        </button>
        {error && <p class="error">{error}</p>}
      </form>
    </main>
  );
}

// MARK: Admin

type StatusFilter = "all" | "edited" | "hidden" | "open";

function Admin({ onSignedOut }: { onSignedOut: () => void }) {
  const [menu, setMenu] = useState<Menu>();
  const [error, setError] = useState<string>();
  const [house, setHouse] = useState(() => localStorageGet("house") ?? "all");
  const [category, setCategory] = useState<SpiritCategory | "all">("all");
  const [status, setStatus] = useState<StatusFilter>("all");
  const [query, setQuery] = useState("");
  const [editingID, setEditingID] = useState<string>();
  const [syncing, setSyncing] = useState(false);
  const [report, setReport] = useState<SyncReport>();
  const [showHistory, setShowHistory] = useState(false);

  async function reload() {
    try {
      setMenu(await api.loadMenu());
      setError(undefined);
    } catch (err) {
      if (err instanceof api.ApiError && err.status === 401) return onSignedOut();
      setError((err as Error).message);
    }
  }
  useEffect(() => void reload(), []);
  useEffect(() => localStorageSet("house", house), [house]);

  const items = useMemo(() => (menu ? buildItems(menu) : []), [menu]);
  // In one house, each bottling shows only that house's bottles.
  const inHouse = useMemo(() => {
    if (house === "all") return items;
    return items.flatMap((i) => {
      const here = i.bottles.filter((b) => (houseFor(b.location) ?? "Unassigned") === house);
      if (here.length === 0) return [];
      return [here.length === i.bottles.length ? i : makeItem(i.product, here, i.override)];
    });
  }, [items, house]);
  const categories = useMemo(() => {
    const counts = new Map<SpiritCategory, number>();
    for (const i of inHouse) counts.set(menuCategory(i.category), (counts.get(menuCategory(i.category)) ?? 0) + 1);
    return (Object.keys(CATEGORY_NAMES) as SpiritCategory[]).filter((c) => counts.has(c)).map((c) => [c, counts.get(c)!] as const);
  }, [inHouse]);
  const shown = inHouse.filter(
    (i) =>
      (category === "all" || menuCategory(i.category) === category) &&
      (status === "all" ||
        (status === "edited" && i.override) ||
        (status === "hidden" && i.isHidden) ||
        (status === "open" && i.openCount > 0)) &&
      matches(i, query),
  );
  const editing = editingID ? items.find((i) => i.product.id === editingID) : undefined;
  const editedCount = items.filter((i) => i.override).length;

  async function signOut() {
    await api.signOut().catch(() => {});
    onSignedOut();
  }

  return (
    <div class="admin">
      <header class="topbar">
        <div>
          <h1>David's Cabinet</h1>
          <p class="muted italic">
            {menu?.syncedAt
              ? `Synced from CellarTracker ${relativeTime(menu.syncedAt)} · ${items.length} bottlings · ${editedCount} edited`
              : "Not synced from CellarTracker yet"}
          </p>
        </div>
        <nav>
          <button onClick={() => setShowHistory(true)}>Sync history</button>
          <button class="primary" onClick={() => setSyncing(true)}>
            Sync
          </button>
          <button class="quiet" onClick={signOut}>
            Sign out
          </button>
        </nav>
      </header>

      <section class="filters">
        <label>
          <span class="caps">House</span>
          <select value={house} onChange={(e) => setHouse(e.currentTarget.value)}>
            <option value="all">Both houses</option>
            <option value="Bedford">Bedford</option>
            <option value="Estancia">Estancia</option>
            <option value="Unassigned">No house</option>
          </select>
        </label>
        <label>
          <span class="caps">Spirit</span>
          <select value={category} onChange={(e) => setCategory(e.currentTarget.value as SpiritCategory | "all")}>
            <option value="all">Everything ({inHouse.length})</option>
            {categories.map(([c, n]) => (
              <option value={c}>
                {c === "scotch" ? "Scotch Whisky" : CATEGORY_NAMES[c]} ({n})
              </option>
            ))}
          </select>
        </label>
        <label>
          <span class="caps">Show</span>
          <select value={status} onChange={(e) => setStatus(e.currentTarget.value as StatusFilter)}>
            <option value="all">All bottlings</option>
            <option value="open">Open bottles</option>
            <option value="edited">Edited</option>
            <option value="hidden">Hidden from the menu</option>
          </select>
        </label>
        <label class="search">
          <span class="caps">Search</span>
          <input
            type="search"
            placeholder="Name, distillery, region or style"
            value={query}
            onInput={(e) => setQuery(e.currentTarget.value)}
          />
        </label>
      </section>

      {error && <p class="error">{error}</p>}
      {!menu && !error && <p class="center muted">Loading the collection…</p>}
      {menu && menu.products.length === 0 && (
        <p class="center muted">No collection yet. Press Sync to download it from CellarTracker.</p>
      )}
      {menu && menu.products.length > 0 && (
        <>
          <p class="caps count">{shown.length === 1 ? "1 bottling" : `${shown.length} bottlings`}</p>
          <ul class="entries">
            {shown.map((i) => (
              <Entry item={i} onSelect={() => setEditingID(i.product.id)} />
            ))}
          </ul>
        </>
      )}

      {editing && (
        <Editor
          item={editing}
          onClose={() => setEditingID(undefined)}
          onSaved={async () => {
            await reload();
            setEditingID(undefined);
          }}
        />
      )}
      {syncing && (
        <SyncDialog
          menu={menu}
          onClose={() => setSyncing(false)}
          onSynced={async (r) => {
            setSyncing(false);
            setReport(r);
            await reload();
          }}
        />
      )}
      {report && <ReportDialog report={report} onClose={() => setReport(undefined)} />}
      {showHistory && <HistoryDialog onClose={() => setShowHistory(false)} onOpen={(r) => setReport(r)} />}
    </div>
  );
}

function Entry({ item, onSelect }: { item: Item; onSelect: () => void }) {
  const sealed = item.bottleCount - item.openCount;
  const kind = item.scotchRegion ? REGION_NAMES[item.scotchRegion] : item.product.region ?? item.product.country;
  return (
    <li>
      <button class="entry" onClick={onSelect}>
        <span class="line">
          <span class="title">{item.title}</span>
          <span class="leader" />
          {item.abv !== undefined && <span class="abv">{formatNumber(item.abv)}%</span>}
        </span>
        {item.subtitle && <span class="subtitle">{item.subtitle}</span>}
        <span class="meta caps">
          <span>{[CATEGORY_NAMES[item.category], kind].filter(Boolean).join(" · ")}</span>
          <span>{item.houses.join(" & ")}</span>
          {item.openCount > 0 && <span class="accent">● Open</span>}
          {sealed > 0 && <span>{sealed} sealed</span>}
          {item.override && <span class="badge">Edited</span>}
          {item.isHidden && <span class="badge dark">Hidden</span>}
        </span>
      </button>
    </li>
  );
}

// MARK: Editing

function Editor({ item, onClose, onSaved }: { item: Item; onClose: () => void; onSaved: () => Promise<void> }) {
  // The item as CellarTracker and the rules alone would show it.
  const base = useMemo(() => makeItem(item.product, item.bottles, undefined), [item]);
  const [title, setTitle] = useState(item.title);
  const [subtitle, setSubtitle] = useState(item.subtitle ?? "");
  const [category, setCategory] = useState<SpiritCategory>(item.category);
  const [region, setRegion] = useState<ScotchRegion | "">(item.override?.scotchRegion ?? item.product.scotchRegion ?? "");
  const [scotchStyle, setScotchStyle] = useState<ScotchStyle>(item.scotchStyle ?? "singleMalt");
  const [abv, setAbv] = useState(item.abv !== undefined ? formatNumber(item.abv) : "");
  const [age, setAge] = useState(item.ageYears !== undefined ? formatNumber(item.ageYears) : "");
  const [style, setStyle] = useState(item.style ?? "");
  const [description, setDescription] = useState(item.description ?? "");
  const [hidden, setHidden] = useState(item.isHidden);
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  /** Only what differs from the CellarTracker values is saved. */
  function buildOverride(): Override | null | "invalid" {
    const abvValue = parseNumber(abv);
    const ageValue = parseNumber(age);
    if (abvValue === "invalid" || ageValue === "invalid") return "invalid";
    const text = (value: string, original: string | undefined, allowEmpty: boolean) => {
      const v = value.trim();
      if (v === (original ?? "")) return undefined;
      if (!v && !allowEmpty) return undefined;
      return v;
    };
    const o: Override = {
      title: text(title, base.title, false),
      subtitle: text(subtitle, base.subtitle, true),
      category: category === base.category ? undefined : category,
      scotchRegion: category === "scotch" && region && region !== item.product.scotchRegion ? region : undefined,
      scotchStyle:
        category === "scotch" && scotchStyle !== (item.product.scotchStyle ?? "singleMalt") ? scotchStyle : undefined,
      abv: abvValue === base.abv ? undefined : abvValue,
      ageYears: ageValue === base.ageYears ? undefined : ageValue,
      style: text(style, base.style, true),
      description: description.trim() || undefined,
      isHidden: hidden,
    };
    for (const key of Object.keys(o) as (keyof Override)[]) if (o[key] === undefined) delete o[key];
    return Object.keys(o).length === 1 && !o.isHidden ? null : o;
  }

  async function save(override: Override | null) {
    setBusy(true);
    setError(undefined);
    try {
      await api.saveOverride(item.product.id, override);
      await onSaved();
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  function submit(e: Event) {
    e.preventDefault();
    const override = buildOverride();
    if (override === "invalid") return setError("ABV and age need to be numbers, e.g. 46 or 12.5.");
    void save(override);
  }

  const placements = groupPlacements(item);

  return (
    <div class="overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <form class="panel" onSubmit={submit}>
        <header>
          <div>
            <p class="caps muted">Edit bottle</p>
            <h2>{item.title}</h2>
          </div>
          <button type="button" class="quiet" onClick={onClose} aria-label="Close">
            ✕
          </button>
        </header>

        <p class="ct-name">
          <span class="caps muted">CellarTracker name</span>
          {item.product.name}
        </p>

        <fieldset>
          <legend class="caps">Menu text</legend>
          <label>
            Title
            <input value={title} placeholder={base.title} onInput={(e) => setTitle(e.currentTarget.value)} />
          </label>
          <label>
            Second line
            <input value={subtitle} placeholder="None" onInput={(e) => setSubtitle(e.currentTarget.value)} />
          </label>
        </fieldset>

        <fieldset>
          <legend class="caps">Details</legend>
          <div class="grid">
            <label>
              Category
              <select value={category} onChange={(e) => setCategory(e.currentTarget.value as SpiritCategory)}>
                {(Object.keys(CATEGORY_NAMES) as SpiritCategory[]).map((c) => (
                  <option value={c}>{c === "americanWhiskey" ? "Other American Whiskey" : CATEGORY_NAMES[c]}</option>
                ))}
              </select>
            </label>
            {category === "scotch" && (
              <>
                <label>
                  Scotch style
                  <select value={scotchStyle} onChange={(e) => setScotchStyle(e.currentTarget.value as ScotchStyle)}>
                    {(Object.keys(STYLE_NAMES) as ScotchStyle[]).map((s) => (
                      <option value={s}>{STYLE_NAMES[s]}</option>
                    ))}
                  </select>
                </label>
                <label>
                  Region
                  <select value={region} onChange={(e) => setRegion(e.currentTarget.value as ScotchRegion | "")}>
                    <option value="">Not set</option>
                    {(Object.keys(REGION_NAMES) as ScotchRegion[]).map((r) => (
                      <option value={r}>{REGION_NAMES[r]}</option>
                    ))}
                  </select>
                </label>
              </>
            )}
            <label>
              ABV %
              <input inputMode="decimal" value={abv} placeholder="Unknown" onInput={(e) => setAbv(e.currentTarget.value)} />
            </label>
            <label>
              Age (years)
              <input
                inputMode="decimal"
                value={age}
                placeholder="No age statement"
                onInput={(e) => setAge(e.currentTarget.value)}
              />
            </label>
          </div>
          <label>
            Style
            <input
              value={style}
              placeholder="e.g. Single Malt Scotch Whisky"
              onInput={(e) => setStyle(e.currentTarget.value)}
            />
          </label>
        </fieldset>

        <fieldset>
          <legend class="caps">Description</legend>
          <textarea
            rows={5}
            value={description}
            placeholder="Tasting notes or a few words for guests"
            onInput={(e) => setDescription(e.currentTarget.value)}
          />
          <p class="hint">Shown on the tasting card.</p>
        </fieldset>

        <label class="check">
          <input type="checkbox" checked={hidden} onChange={(e) => setHidden(e.currentTarget.checked)} />
          Hide from the menu
        </label>

        <section class="where">
          <p class="caps muted">Where</p>
          {placements.map(([place, count]) => (
            <p class="line">
              <span>{place}</span>
              <span class="leader" />
              <span class="muted">{count === 1 ? "1 bottle" : `${count} bottles`}</span>
            </p>
          ))}
          {/^\d+$/.test(item.product.id) && (
            <a href={`https://www.cellartracker.com/wine.asp?iWine=${item.product.id}`} target="_blank" rel="noopener noreferrer">
              View on CellarTracker ↗
            </a>
          )}
        </section>

        {error && <p class="error">{error}</p>}

        <footer>
          <button
            type="button"
            class="danger"
            disabled={!item.override || busy}
            onClick={() => confirm("Remove all edits to this bottle?") && void save(null)}
          >
            Reset to CellarTracker
          </button>
          <span class="spacer" />
          <button type="button" onClick={onClose}>
            Cancel
          </button>
          <button class="primary" disabled={busy}>
            {busy ? "Saving…" : "Save"}
          </button>
        </footer>
        <p class="hint">Edits are shared with every iPad. They never change CellarTracker and survive every sync.</p>
      </form>
    </div>
  );
}

function groupPlacements(item: Item): [string, number][] {
  const counts = new Map<string, number>();
  for (const b of item.bottles) {
    const key = placement(b.location, b.bin);
    counts.set(key, (counts.get(key) ?? 0) + b.quantity);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

function parseNumber(text: string): number | undefined | "invalid" {
  const cleaned = text.replace("%", "").replace(",", ".").trim();
  if (!cleaned) return undefined;
  const value = Number(cleaned);
  return Number.isFinite(value) && value >= 0 && value <= 100 ? value : "invalid";
}

// MARK: Sync

function SyncDialog({
  menu,
  onClose,
  onSynced,
}: {
  menu: Menu | undefined;
  onClose: () => void;
  onSynced: (report: SyncReport) => Promise<void>;
}) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function submit(e: Event) {
    e.preventDefault();
    setBusy(true);
    setError(undefined);
    try {
      await onSynced(await api.syncFromCellarTracker(username.trim(), password, menu));
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <div class="overlay" onClick={(e) => e.target === e.currentTarget && !busy && onClose()}>
      <form class="panel narrow" onSubmit={submit}>
        <header>
          <div>
            <p class="caps muted">Sync</p>
            <h2>Update from CellarTracker</h2>
          </div>
        </header>
        <p class="hint">
          Your browser can remember this login. It's sent to the cabinet server for this sync only, used once to
          download the collection, and never stored there.
        </p>
        <label>
          CellarTracker username
          <input
            name="username"
            autocomplete="username"
            value={username}
            onInput={(e) => setUsername(e.currentTarget.value)}
            autofocus
          />
        </label>
        <label>
          Password
          <input
            name="password"
            type="password"
            autocomplete="current-password"
            value={password}
            onInput={(e) => setPassword(e.currentTarget.value)}
          />
        </label>
        {error && <p class="error">{error}</p>}
        <footer>
          <span class="spacer" />
          <button type="button" onClick={onClose} disabled={busy}>
            Cancel
          </button>
          <button class="primary" disabled={!username.trim() || !password || busy}>
            {busy ? "Syncing…" : "Sync"}
          </button>
        </footer>
      </form>
    </div>
  );
}

function ReportDialog({ report, onClose }: { report: SyncReport; onClose: () => void }) {
  const hasChanges = report.added.length + report.increased.length + report.decreased.length + report.removed.length > 0;
  return (
    <div class="overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div class="panel">
        <header>
          <div>
            <h2>Sync Report</h2>
            <p class="muted italic">
              {new Date(report.date).toLocaleString()} · {report.productCount} products · {report.bottleCount} bottles
            </p>
          </div>
          <button class="primary" onClick={onClose}>
            Done
          </button>
        </header>
        {report.isInitial ? (
          <p>The collection is now coming from CellarTracker. Future syncs will list what changed.</p>
        ) : !hasChanges ? (
          <p>Nothing has changed since the last sync.</p>
        ) : (
          <>
            <ChangeGroup title="New to the collection" changes={report.added} detail={(c) => bottles(c.after)} />
            <ChangeGroup title="More bottles" changes={report.increased} detail={(c) => `${c.before} → ${c.after}`} />
            <ChangeGroup title="Fewer bottles" changes={report.decreased} detail={(c) => `${c.before} → ${c.after}`} />
            <ChangeGroup title="Gone" changes={report.removed} detail={(c) => `was ${bottles(c.before)}`} />
          </>
        )}
      </div>
    </div>
  );
}

const bottles = (n: number) => (n === 1 ? "1 bottle" : `${n} bottles`);

function ChangeGroup({
  title,
  changes,
  detail,
}: {
  title: string;
  changes: SyncChange[];
  detail: (c: SyncChange) => string;
}) {
  if (changes.length === 0) return null;
  return (
    <section class="changes">
      <h3 class="section-heading">
        {title} ({changes.length})
      </h3>
      {changes.map((c) => (
        <div class="change">
          <p class="line">
            <span class="title">{c.title}</span>
            <span class="leader" />
            <span class="muted">{detail(c)}</span>
          </p>
          <p class="subtitle">{[c.subtitle, CATEGORY_NAMES[c.category]].filter(Boolean).join(" · ")}</p>
        </div>
      ))}
    </section>
  );
}

function HistoryDialog({ onClose, onOpen }: { onClose: () => void; onOpen: (r: SyncReport) => void }) {
  const [history, setHistory] = useState<api.SyncHistoryEntry[]>();
  const [error, setError] = useState<string>();
  useEffect(() => {
    api.syncHistory().then(setHistory, (err) => setError((err as Error).message));
  }, []);
  return (
    <div class="overlay" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div class="panel narrow">
        <header>
          <div>
            <h2>Sync history</h2>
            <p class="muted italic">The last 20 syncs, from any device</p>
          </div>
          <button class="primary" onClick={onClose}>
            Done
          </button>
        </header>
        {error && <p class="error">{error}</p>}
        {history?.length === 0 && <p class="muted">No syncs yet.</p>}
        {history?.map((h) => {
          const r = h.report;
          const summary = r.isInitial
            ? "First sync"
            : [
                r.added.length && `${r.added.length} new`,
                r.increased.length && `${r.increased.length} more`,
                r.decreased.length && `${r.decreased.length} fewer`,
                r.removed.length && `${r.removed.length} gone`,
              ]
                .filter(Boolean)
                .join(", ") || "No changes";
          return (
            <button class="history-row" onClick={() => onOpen(r)}>
              <span>{new Date(h.syncedAt).toLocaleString()}</span>
              <span class="muted">
                {summary} · {h.bottleCount} bottles
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

// MARK: Helpers

function relativeTime(iso: string): string {
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  const format = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
  if (seconds < 60) return "just now";
  if (seconds < 3600) return format.format(-Math.round(seconds / 60), "minute");
  if (seconds < 86400) return format.format(-Math.round(seconds / 3600), "hour");
  return format.format(-Math.round(seconds / 86400), "day");
}

function localStorageGet(key: string): string | null {
  try {
    return localStorage.getItem(`cabinet.${key}`);
  } catch {
    return null;
  }
}

function localStorageSet(key: string, value: string) {
  try {
    localStorage.setItem(`cabinet.${key}`, value);
  } catch {
    // Private browsing etc.: the choice just isn't remembered.
  }
}

render(<App />, document.getElementById("app")!);
