// Big Picture and in-game overlay windows, shared by the battery badge and the
// home music.
import { Millennium } from 'millennium';

const HUB_KEY = '__couchModeWindowHub_v1';

export function contextKind(context: any): 'main' | 'overlay' | null {
	const name = String(context?.m_strName || '');
	const title = String(context?.m_strTitle || '');
	if (/^SP BPM(?:_|$)/.test(name) || title === 'Steam Big Picture Mode') return 'main';
	// Steam appends _uid<PID> to the in-game overlay's internal window name.
	if (/^gamepadoverlay(?:_|$)/.test(name)) return 'overlay';
	return null;
}

// Millennium's window hook has no removal API, so one bridge is registered
// per Steam UI lifetime and plugin reloads only swap the subscriber.
export function subscribePopups(callback: (context: any) => void) {
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
