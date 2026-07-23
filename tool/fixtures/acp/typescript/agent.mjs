import * as acp from "@agentclientprotocol/sdk";
import { Readable, Writable } from "node:stream";

let nextSession = 1;

const stream = acp.ndJsonStream(
  Writable.toWeb(process.stdout),
  Readable.toWeb(process.stdin),
);

acp
  .agent({ name: "pigcode-fixed-typescript-peer" })
  .onRequest("initialize", () => ({
    protocolVersion: acp.PROTOCOL_VERSION,
    agentCapabilities: { loadSession: false },
    agentInfo: {
      name: "pigcode-fixed-typescript-peer",
      version: "1.3.0",
    },
  }))
  .onRequest("session/new", () => ({
    sessionId: `typescript-session-${nextSession++}`,
  }))
  .onRequest("session/prompt", async (ctx) => {
    const read = await ctx.client.request("fs/read_text_file", {
      sessionId: ctx.params.sessionId,
      path: "README.md",
    });
    await ctx.client.notify("session/update", {
      sessionId: ctx.params.sessionId,
      update: {
        sessionUpdate: "agent_message_chunk",
        content: {
          type: "text",
          text: `typescript peer: ${read.content}`,
        },
      },
    });
    return { stopReason: "end_turn" };
  })
  .connect(stream);
