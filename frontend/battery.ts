// Battery badge next to the clock in Big Picture and in the in-game overlay.
import { findModule, Millennium } from 'millennium';
import { fromBackend } from './json';

const BADGE_ID = 'big-picture-controller-battery-badge';
const POLL_MS = 10000;
const HUB_KEY = '__bigPictureControllerBatteryHub_v1';

type Battery = { status: string; percent?: number; name?: string; message?: string };
type Entry = {
	frame: number | null;
	observer: MutationObserver | null;
	begin: () => void;
	changed: () => void;
	unload: () => void;
};

let battery: Battery = { status: 'starting' };
let alive = false;
let timer: number | null = null;
let headerClasses: any = null;
let unsubscribe: (() => void) | null = null;
const docs = new Map<Document, Entry>();

function contextKind(context: any): 'main' | 'overlay' | null {
	const name = String(context?.m_strName || '');
	const title = String(context?.m_strTitle || '');
	if (/^SP BPM(?:_|$)/.test(name) || title === 'Steam Big Picture Mode') return 'main';
	// Steam appends _uid<PID> to the in-game overlay's internal window name.
	if (/^gamepadoverlay(?:_|$)/.test(name)) return 'overlay';
	return null;
}

function classes() {
	if (!headerClasses) {
		try {
			headerClasses = findModule((m: any) => m && typeof m === 'object' &&
				typeof m.Clock === 'string' && typeof m.Header === 'string' &&
				typeof m.DashboardBar === 'string' && typeof m.HeaderItem === 'string') || null;
		} catch { /* Steam may rename the module; fall back to a class name match. */ }
	}
	return headerClasses;
}

function findClock(doc: Document): HTMLElement | null {
	const css = classes();
	const candidates = Array.from(css ? doc.getElementsByClassName(css.Clock) :
		doc.querySelectorAll('[class*="Clock"]')) as HTMLElement[];
	return candidates.filter(el => {
		const r = el.getBoundingClientRect();
		return /\b([01]?\d|2[0-3]):[0-5]\d\b/.test(el.textContent || '') &&
			r.top >= 0 && r.top < 120 && r.width > 0 && r.height > 0;
	}).sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left)[0] || null;
}

function makeBadge(doc: Document) {
	const badge = doc.createElement('div');
	badge.id = BADGE_ID;
	badge.className = classes()?.HeaderItem || 'HeaderItem';
	badge.setAttribute('role', 'img');
	Object.assign(badge.style, {
		display: 'none', alignItems: 'center', gap: '5px', padding: '0 8px',
		color: 'inherit', fontFamily: 'inherit', fontSize: '14px', fontWeight: '600',
		lineHeight: 'normal', whiteSpace: 'nowrap', pointerEvents: 'none',
		userSelect: 'none', flex: '0 0 auto', boxSizing: 'border-box',
		minWidth: '0', maxWidth: '86px', overflow: 'hidden',
	});
	// Controller outline. There is no charging symbol: Windows does not report charging here.
	const ns = 'http://www.w3.org/2000/svg';
	const svg = doc.createElementNS(ns, 'svg');
	svg.setAttribute('viewBox', '0 0 24 24');
	svg.setAttribute('width', '20');
	svg.setAttribute('height', '20');
	svg.setAttribute('aria-hidden', 'true');
	svg.style.flex = '0 0 auto';
	const outline = doc.createElementNS(ns, 'path');
	outline.setAttribute('d', 'M7 7h10c2 0 3 2 4 7l.5 3c.3 2-2 3-3 1l-2-3h-9l-2 3c-1 2-3.3 1-3-1L3 14c1-5 2-7 4-7Z');
	outline.setAttribute('fill', 'none');
	outline.setAttribute('stroke', 'currentColor');
	outline.setAttribute('stroke-width', '1.5');
	const controls = doc.createElementNS(ns, 'path');
	controls.setAttribute('d', 'M7 10v4m-2-2h4m7-1h.1m2 2h.1');
	controls.setAttribute('stroke', 'currentColor');
	controls.setAttribute('stroke-width', '2');
	controls.setAttribute('stroke-linecap', 'round');
	svg.append(outline, controls);
	const label = doc.createElement('span');
	label.dataset.batteryLabel = 'true';
	badge.append(svg, label);
	return badge;
}

function render(doc: Document) {
	if (!docs.has(doc) || !alive) return;
	if (!doc.defaultView || doc.defaultView.closed) { detach(doc); return; }
	const clock = findClock(doc);
	let badge = doc.getElementById(BADGE_ID);
	if (!clock?.parentElement) { if (badge) badge.style.display = 'none'; return; }
	if (!badge) badge = makeBadge(doc);
	if (badge.parentElement !== clock.parentElement || badge.nextElementSibling !== clock)
		clock.parentElement.insertBefore(badge, clock);
	if (battery.status !== 'connected' || typeof battery.percent !== 'number') {
		badge.style.display = 'none';
		return;
	}
	const text = `${battery.percent}%`;
	const label = badge.querySelector('[data-battery-label]')!;
	if (label.textContent !== text) label.textContent = text;
	const title = `${battery.name || 'Controller'}: ${text}`;
	if (badge.title !== title) { badge.title = title; badge.setAttribute('aria-label', title); }
	badge.style.display = 'inline-flex';
	// Stay in the normal header layout; hide rather than overlap if the row is full.
	const parent = clock.parentElement, r = badge.getBoundingClientRect();
	const width = doc.defaultView.innerWidth;
	if (r.left < 0 || r.right > width || (parent.clientWidth > 0 && parent.scrollWidth > parent.clientWidth + 1))
		badge.style.display = 'none';
}

function schedule(doc: Document) {
	const entry = docs.get(doc);
	if (!entry || entry.frame !== null || !alive || !doc.defaultView) return;
	entry.frame = doc.defaultView.requestAnimationFrame(() => {
		entry.frame = null;
		try { render(doc); } catch (error) { console.warn('Battery badge render failed', error); }
	});
}

function detach(doc: Document) {
	const entry = docs.get(doc);
	if (!entry) return;
	entry.observer?.disconnect();
	if (entry.frame !== null) doc.defaultView?.cancelAnimationFrame(entry.frame);
	doc.removeEventListener('DOMContentLoaded', entry.begin);
	doc.removeEventListener('visibilitychange', entry.changed);
	doc.defaultView?.removeEventListener('resize', entry.changed);
	doc.defaultView?.removeEventListener('beforeunload', entry.unload);
	doc.getElementById(BADGE_ID)?.remove();
	docs.delete(doc);
}

function attach(context: any) {
	const kind = contextKind(context), doc: Document | undefined = context?.m_popup?.document;
	if (!alive || !kind || !doc?.defaultView || doc.defaultView.closed || docs.has(doc)) return;
	const view = doc.defaultView as Window & typeof globalThis;
	const entry: Entry = { frame: null, observer: null, begin: () => {}, changed: () => schedule(doc), unload: () => detach(doc) };
	docs.set(doc, entry);
	entry.begin = () => {
		if (!alive || !docs.has(doc) || entry.observer) return;
		entry.observer = new view.MutationObserver(records => {
			// Ignore our own label updates; Steam mounts its header asynchronously.
			if (records.some(r => !(r.target as Element).closest?.(`#${BADGE_ID}`))) schedule(doc);
		});
		entry.observer.observe(doc.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style'] });
		schedule(doc);
	};
	doc.addEventListener('visibilitychange', entry.changed);
	view.addEventListener('resize', entry.changed);
	view.addEventListener('beforeunload', entry.unload);
	if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', entry.begin, { once: true });
	else entry.begin();
}

// Millennium's window hook has no removal API, so one bridge is registered
// per Steam UI lifetime and plugin reloads only swap the subscriber.
function subscribePopups(callback: (context: any) => void) {
	const w = window as any;
	let hub = w[HUB_KEY];
	if (!hub) {
		hub = w[HUB_KEY] = { subscribers: new Set(), contexts: new Set(), seen: new WeakSet(), registered: false };
		hub.dispatch = (context: any) => {
			if (!contextKind(context) || !context?.m_popup?.document) return;
			for (const ref of hub.contexts) {
				const old = ref.deref();
				if (!old?.m_popup || old.m_popup.closed) hub.contexts.delete(ref);
			}
			if (!hub.seen.has(context)) { hub.seen.add(context); hub.contexts.add(new WeakRef(context)); }
			for (const fn of hub.subscribers) fn(context);
		};
	}
	hub.subscribers.add(callback);
	if (!hub.registered) {
		if (typeof Millennium?.AddWindowCreateHook !== 'function') {
			hub.subscribers.delete(callback);
			throw new Error('Millennium AddWindowCreateHook unavailable');
		}
		Millennium.AddWindowCreateHook(hub.dispatch);
		hub.registered = true;
	} else {
		for (const ref of hub.contexts) {
			const context = ref.deref(), doc = context?.m_popup?.document;
			if (!doc?.defaultView || doc.defaultView.closed) hub.contexts.delete(ref);
			else callback(context);
		}
	}
	return () => { hub.subscribers.delete(callback); };
}

async function poll() {
	if (!alive) return;
	try {
		battery = fromBackend<Battery>(await backend.getBattery());
	} catch (error) {
		battery = { status: 'unavailable', message: String(error) };
	}
	if (!alive) return;
	for (const doc of docs.keys()) schedule(doc);
	timer = window.setTimeout(poll, POLL_MS);
}

export function startBattery() {
	alive = true;
	unsubscribe = subscribePopups(attach);
	void poll();
}

export function stopBattery() {
	alive = false;
	if (timer !== null) window.clearTimeout(timer);
	timer = null;
	unsubscribe?.();
	unsubscribe = null;
	for (const doc of Array.from(docs.keys())) detach(doc);
}
