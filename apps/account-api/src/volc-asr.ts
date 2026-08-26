export type VolcAsrTokenPayload = {
	appId: string;
	resourceId: string;
	token: string;
	expireAt: string;
};

export function readVolcAsrConfig(): VolcAsrTokenPayload | null {
	const appId = process.env.VOLC_ASR_APP_ID?.trim();
	const rawToken = process.env.VOLC_ASR_TOKEN?.trim();
	const resourceId =
		process.env.VOLC_ASR_RESOURCE_ID?.trim() || "volc.bigasr.sauc.duration";
	if (!appId || !rawToken) return null;
	const token = rawToken.startsWith("Bearer;") ? rawToken.slice("Bearer;".length) : rawToken;
	return {
		appId,
		resourceId,
		token,
		expireAt: new Date(Date.now() + 3_600_000).toISOString(),
	};
}
