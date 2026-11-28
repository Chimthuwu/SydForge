// SydForge multiplayer relay: one Durable Object per room passing JSON between
// players. Same method and message envelope as SKYJUMP3D's relay.
const MAX_ROOM = 8;
const MAX_PAYLOAD = 16 * 1024;

export class Room {
  constructor(ctx) { this.ctx = ctx; }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') return new Response('expected websocket', { status: 426 });
    const live = this.ctx.getWebSockets();
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    if (live.length >= MAX_ROOM) {
      this.ctx.acceptWebSocket(server);
      server.send(JSON.stringify({ t: 'full' }));
      server.close(1000, 'full');
      return new Response(null, { status: 101, webSocket: client });
    }
    const id = await this.ctx.blockConcurrencyWhile(async () => {
      const n = ((await this.ctx.storage.get('next')) ?? 0) + 1;
      await this.ctx.storage.put('next', n);
      return n;
    });
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ id });
    const peers = live.map((w) => w.deserializeAttachment()?.id).filter(Boolean);
    server.send(JSON.stringify({ t: 'hi', id, peers }));
    this.broadcast({ t: 'join', id }, id);
    return new Response(null, { status: 101, webSocket: client });
  }

  broadcast(m, exceptId) {
    const data = JSON.stringify(m);
    for (const w of this.ctx.getWebSockets()) {
      if (w.deserializeAttachment()?.id !== exceptId) { try { w.send(data); } catch {} }
    }
  }

  webSocketMessage(ws, data) {
    const id = ws.deserializeAttachment()?.id;
    if (!id || typeof data !== 'string' || data.length > MAX_PAYLOAD) return;
    let m;
    try { m = JSON.parse(data); } catch { return; }
    if (!m || typeof m !== 'object' || typeof m.t !== 'string') return;
    m.from = id; // stamped here so clients can't spoof it
    if (m.to) {
      const target = this.ctx.getWebSockets().find((w) => w.deserializeAttachment()?.id === (m.to | 0));
      if (target) try { target.send(JSON.stringify(m)); } catch {}
    } else this.broadcast(m, id);
  }

  webSocketClose(ws) { this.left(ws); }
  webSocketError(ws) { this.left(ws); }

  left(ws) {
    const id = ws.deserializeAttachment()?.id;
    if (id) this.broadcast({ t: 'leave', id }, id);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/ws') {
      const name = (url.searchParams.get('room') || 'lobby').replace(/[^\w-]/g, '').slice(0, 24) || 'lobby';
      return env.ROOMS.get(env.ROOMS.idFromName(name)).fetch(request);
    }
    return new Response('SydForge relay', { status: url.pathname === '/' ? 200 : 404 });
  },
};
