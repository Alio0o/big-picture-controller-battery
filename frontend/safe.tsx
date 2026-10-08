// Keeps a rendering problem in this plugin from taking down Steam's own UI.
// Steam's components are looked up at runtime and can be missing in some
// windows or Steam versions; React then throws while rendering.
import { Component, ReactNode } from 'react';

export class SafeBoundary extends Component<{ children?: ReactNode; fallback?: ReactNode }, { failed: boolean }> {
	state = { failed: false };

	static getDerivedStateFromError() {
		return { failed: true };
	}

	componentDidCatch(error: unknown) {
		console.error('Big Picture Controller Battery: settings UI failed to render', error);
	}

	render() {
		return this.state.failed ? (this.props.fallback ?? null) : this.props.children;
	}
}

// True when every value is something React can render as a component.
export function renderable(...components: unknown[]) {
	return components.every(c => typeof c === 'function' || (typeof c === 'object' && c !== null));
}
