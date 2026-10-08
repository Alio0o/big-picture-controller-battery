// Millennium already turns a JSON string returned by the backend into an
// object, so accept either form.
export function fromBackend<T>(value: unknown): T {
	return (typeof value === 'string' ? JSON.parse(value) : value) as T;
}
