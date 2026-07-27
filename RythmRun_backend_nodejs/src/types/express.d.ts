export {};

declare global {
    namespace Express {
        interface Request {
            user?: {
                id: number;
                sessionId: string;
                tokenId: string;
            };
            /**
             * Server-minted correlation id for one request. Always generated
             * here; a client-supplied header is never trusted, so it cannot be
             * used to forge or collide with another request's log trail.
             */
            requestId?: string;
        }
    }
}
