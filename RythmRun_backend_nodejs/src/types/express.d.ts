export {};

declare global {
    namespace Express {
        interface Request {
            user?: {
                id: number;
                sessionId: string;
                tokenId: string;
            };
        }
    }
}
