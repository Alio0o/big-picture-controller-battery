// Background music in Big Picture.
//
// The music is the user's own file or folder (see backend/music.lua). It
// plays everywhere in Big Picture, including its menus, and fades out on the
// store (it has trailers and music of its own), while a video plays, while a
// game runs, and while another program is in front. It fades back in where it
// stopped. Optionally it also plays in the overlay over a muted game.
import { onSettings, settings } from './config';
import { fromBackend } from './json';
import { overlayOpen } from './mute';
import { gameRunning } from './steam';
import { contextKind, subscribePopups } from './windows';

type Track = { path: string; name: string; size: number; type: string };
export type MusicList = { folder: string; tracks: Track[]; files: number; chosen: string; error?: string };

const TICK_MS = 250;
const FADE_MS = 1200;
const RELIST_MS = 10000;

let alive = false;
let timer: number | null = null;
let unsubscribe: (() => void) | null = null;
let unsubscribeSettings: (() => void) | null = null;
const windows = new Set<Document>();
const kindOf = new WeakMap<Document, 'main' | 'overlay'>();

let audio: HTMLAudioElement | null = null;
let list: MusicList | null = null;
let listing: Promise<void> | null = null;
let listedAt = 0;
let index = 0;
let loadedPath = '';
let loading: Promise<void> | null = null;
let objectUrl = '';
let level = 0;
let lastReason = '';
let warnedPath = false;
let lastPage = '';
let steamFront = true;
let frontAsking = false;
let warnedPlay = false;

export async function listMusic(): Promise<MusicList> {
	const value = fromBackend<any>(await backend.getMusic());
	return {
		folder: String(value?.folder || ''),
		tracks: Array.isArray(value?.tracks) ? value.tracks : [],
		files: Number(value?.files) || 0,
		chosen: String(value?.chosen || ''),
		error: value?.error,
	};
}

function refreshList() {
	listing ??= listMusic()
		.then(value => { list = value; index = 0; listedAt = Date.now(); })
		.catch(error => { list = { folder: '', tracks: [], files: 0, chosen: '', error: String(error) }; listedAt = Date.now(); })
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
	if (typeof path === 'string') {
		const clean = path.replace(/^\/routes(?=\/)/, '');
		if (clean !== lastPage) { lastPage = clean; console.log('Couch Mode music: page', clean); }
		return clean;
	}
	if (!warnedPath) {
		warnedPath = true;
		console.warn('Couch Mode music: Big Picture page unknown, so the store is noticed only by its videos.');
	}
	return null;
}

// The store has its own trailers and music. Its pages open in Steam's web
// browser view, which Couch Mode cannot look into, so they go by the path.
function storePage(path: string | null): boolean {
	return path !== null && /(^|\/)(store|steamweb|externalweb|browser)(\/|$)/i.test(path);
}

function mediaPlaying(): boolean {
	for (const doc of [document, ...windows]) {
		for (const el of Array.from(doc.querySelectorAll('video, audio')) as HTMLMediaElement[]) {
			if (el !== audio && !el.paused && !el.ended && !el.muted && el.volume > 0) return true;
		}
	}
	return false;
}

function bigPictureOpen(): boolean {
	for (const doc of windows) {
		if (!doc.defaultView || doc.defaultView.closed) { windows.delete(doc); continue; }
		if (kindOf.get(doc) === 'main') return true;
	}
	return false;
}

// Asks Windows (through the backend) whether a Steam window is in front.
// Big Picture's menus and popups are Steam windows too, so they count.
function pollFront() {
	if (!alive || frontAsking) return;
	frontAsking = true;
	backend.steamInFront()
		.then(answer => { steamFront = answer !== 'no'; })
		.catch(() => { steamFront = true; })
		.finally(() => { frontAsking = false; });
}

// Why the music should not play right now, or '' to play.
function reason(): string {
	const s = settings();
	if (!s?.music) return 'off';
	if (!list) { refreshList(); return 'loading the list'; }
	if (list.tracks.length === 0) {
		// Look again now and then, so music added to the folder starts playing.
		if (Date.now() - listedAt > RELIST_MS) refreshList();
		return list.error || 'no music';
	}
	if (overlayOpen()) {
		// Over a game the overlay is in front, not Steam, so focus is not checked.
		if (!s.music_in_overlay) return 'the game overlay is open (music in the overlay is off)';
		// Only over a muted game, so the two do not play at once.
		if (!s.game_mute) return 'the game overlay is open (game mute is off)';
	} else {
		if (gameRunning()) return 'a game is running';
		if (!bigPictureOpen()) return 'Big Picture is not open';
		pollFront();
		if (!steamFront) return 'Steam is not in front';
		if (storePage(currentPath())) return 'on the store';
	}
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
	const volume = Math.max(0, Math.min(100, settings()?.music_volume ?? 30)) / 100;
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
	let lastFile = settings()?.music_file;
	unsubscribeSettings = onSettings(s => {
		if (s.music_file !== lastFile) { lastFile = s.music_file; list = null; releaseTrack(); }
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
