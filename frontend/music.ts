// Background music on the Big Picture Home and Library pages.
//
// The music is the user's own file or folder (see backend/music.lua). It
// fades out on any other page (the store has trailers), while a video plays,
// while a game runs, and while Big Picture is not in front, and fades back in
// where it stopped.
import { onSettings, settings } from './config';
import { fromBackend } from './json';
import { overlayOpen } from './mute';
import { gameRunning } from './steam';
import { contextKind, subscribePopups } from './windows';

type Track = { path: string; name: string; size: number; type: string };
export type MusicList = { folder: string; tracks: Track[]; error?: string };

const TICK_MS = 250;
const FADE_MS = 1200;

let alive = false;
let timer: number | null = null;
let unsubscribe: (() => void) | null = null;
let unsubscribeSettings: (() => void) | null = null;
const windows = new Set<Document>();
const kindOf = new WeakMap<Document, 'main' | 'overlay'>();

let audio: HTMLAudioElement | null = null;
let list: MusicList | null = null;
let listing: Promise<void> | null = null;
let index = 0;
let loadedPath = '';
let loading: Promise<void> | null = null;
let objectUrl = '';
let level = 0;
let lastReason = '';
let warnedPath = false;
let warnedPlay = false;

export async function listMusic(): Promise<MusicList> {
	const value = fromBackend<any>(await backend.getMusic());
	return { folder: String(value?.folder || ''), tracks: Array.isArray(value?.tracks) ? value.tracks : [], error: value?.error };
}

function refreshList() {
	listing ??= listMusic()
		.then(value => { list = value; index = 0; })
		.catch(error => { list = { folder: '', tracks: [], error: String(error) }; })
		.finally(() => { listing = null; });
}

function releaseTrack() {
	audio?.pause();
	audio?.removeAttribute('src');
	audio?.load();
	if (objectUrl) URL.revokeObjectURL(objectUrl);
	objectUrl = '';
	loadedPath = '';
}

// Reads the file from the backend in pieces and hands it to the player.
async function loadTrack(track: Track) {
	const parts: Uint8Array[] = [];
	let offset = 0;
	while (offset < track.size) {
		const piece = await backend.readMusic(track.path, offset);
		if (!alive || typeof piece !== 'string' || piece === '') break;
		const text = atob(piece);
		const bytes = new Uint8Array(text.length);
		for (let i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i);
		parts.push(bytes);
		offset += bytes.length;
	}
	// Stopped, or the music setting changed while reading.
	if (!alive || list?.tracks[index]?.path !== track.path) return;
	if (offset !== track.size) throw new Error(`could not read ${track.name}`);
	releaseTrack();
	objectUrl = URL.createObjectURL(new Blob(parts as BlobPart[], { type: track.type }));
	loadedPath = track.path;
	const player = audio!;
	player.loop = (list?.tracks.length || 0) <= 1;
	player.src = objectUrl;
	player.volume = 0;
}

function ensureTrack() {
	const track = list?.tracks[index];
	if (!track || loading || loadedPath === track.path) return;
	loading = loadTrack(track)
		.catch(error => {
			console.warn('Couch Mode music:', error);
			// Skip a file that cannot be read rather than trying it forever.
			if (list) list = { ...list, tracks: list.tracks.filter(t => t !== track) };
			index = 0;
		})
		.finally(() => { loading = null; });
}

function nextTrack() {
	const count = list?.tracks.length || 0;
	if (count <= 1) return;
	index = (index + 1) % count;
	releaseTrack();
}

// Big Picture's page path, for example /library/home. Null when Steam does
// not say.
function currentPath(): string | null {
	const instance = (window as any).SteamUIStore?.WindowStore?.GamepadUIMainWindowInstance;
	const path = instance?.m_history?.location?.pathname;
	if (typeof path === 'string') return path.replace(/^\/routes(?=\/)/, '');
	if (!warnedPath) {
		warnedPath = true;
		console.warn('Couch Mode music: Big Picture page unknown, so it only pauses for videos, games and focus.');
	}
	return null;
}

function pageAllowsMusic(path: string | null): boolean {
	return path === null || path === '/' || /^\/(library|home)(\/|$)/.test(path);
}

function mediaPlaying(): boolean {
	for (const doc of [document, ...windows]) {
		for (const el of Array.from(doc.querySelectorAll('video, audio')) as HTMLMediaElement[]) {
			if (el !== audio && !el.paused && !el.ended && !el.muted && el.volume > 0) return true;
		}
	}
	return false;
}

function bigPicture(): Document | null {
	for (const doc of windows) {
		if (!doc.defaultView || doc.defaultView.closed) { windows.delete(doc); continue; }
		if (doc.visibilityState === 'visible' && kindOf.get(doc) === 'main') return doc;
	}
	return null;
}

// Why the music should not play right now, or '' to play.
function reason(): string {
	const s = settings();
	if (!s?.music) return 'off';
	if (!list) { refreshList(); return 'loading the list'; }
	if (list.tracks.length === 0) return list.error || 'no music';
	if (gameRunning() || overlayOpen()) return 'a game is running';
	const doc = bigPicture();
	if (!doc) return 'Big Picture is not open';
	if (!doc.hasFocus()) return 'Big Picture is not in front';
	const path = currentPath();
	if (!pageAllowsMusic(path)) return `on ${path}`;
	if (mediaPlaying()) return 'a video is playing';
	return '';
}

function tick() {
	if (!alive || !audio) return;
	let why = 'error';
	try { why = reason(); } catch (error) { console.warn('Couch Mode music check failed', error); }
	if (why !== lastReason) {
		console.log('Couch Mode music:', why || 'playing');
		lastReason = why;
	}
	const target = why ? 0 : 1;
	const step = TICK_MS / FADE_MS;
	level = target > level ? Math.min(target, level + step) : Math.max(target, level - step);

	if (target > 0) ensureTrack();
	const volume = Math.max(0, Math.min(100, settings()?.music_volume ?? 40)) / 100;
	audio.volume = level * level * volume; // fades sound even to the ear
	if (level > 0 && audio.paused && loadedPath) {
		audio.play().catch(error => {
			if (!warnedPlay) { warnedPlay = true; console.warn('Couch Mode music could not start', error); }
		});
	} else if (level === 0 && !audio.paused) {
		audio.pause();
	}
	timer = window.setTimeout(tick, TICK_MS);
}

function track(context: any) {
	const kind = contextKind(context), doc: Document | undefined = context?.m_popup?.document;
	if (!alive || !kind || !doc?.defaultView || doc.defaultView.closed) return;
	kindOf.set(doc, kind);
	windows.add(doc);
}

export function startMusic() {
	alive = true;
	audio = new Audio();
	audio.preload = 'auto';
	audio.addEventListener('ended', nextTrack);
	unsubscribe = subscribePopups(track);
	let lastPath = settings()?.music_path;
	unsubscribeSettings = onSettings(s => {
		if (s.music_path !== lastPath) { lastPath = s.music_path; list = null; releaseTrack(); }
	});
	tick();
}

export function stopMusic() {
	alive = false;
	if (timer !== null) window.clearTimeout(timer);
	timer = null;
	unsubscribe?.();
	unsubscribe = null;
	unsubscribeSettings?.();
	unsubscribeSettings = null;
	releaseTrack();
	audio?.removeEventListener('ended', nextTrack);
	audio = null;
	list = null;
	windows.clear();
	level = 0;
	lastReason = '';
}
