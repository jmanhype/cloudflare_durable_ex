var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// .wrangler/tmp/bundle-xtvoLe/checked-fetch.js
var urls = /* @__PURE__ */ new Set();
function checkURL(request, init) {
  const url = request instanceof URL ? request : new URL(
    (typeof request === "string" ? new Request(request, init) : request).url
  );
  if (url.port && url.port !== "443" && url.protocol === "https:") {
    if (!urls.has(url.toString())) {
      urls.add(url.toString());
      console.warn(
        `WARNING: known issue with \`fetch()\` requests to custom HTTPS ports in published Workers:
 - ${url.toString()} - the custom port will be ignored when the Worker is published using the \`wrangler deploy\` command.
`
      );
    }
  }
}
__name(checkURL, "checkURL");
globalThis.fetch = new Proxy(globalThis.fetch, {
  apply(target, thisArg, argArray) {
    const [request, init] = argArray;
    checkURL(request, init);
    return Reflect.apply(target, thisArg, argArray);
  }
});

// benchmark_worker.js
var BenchmarkDurableObject = class {
  constructor(state, env) {
    this.state = state;
    this.storage = state.storage;
    this.sessions = /* @__PURE__ */ new Map();
  }
  // Handle HTTP requests
  async fetch(request) {
    const url = new URL(request.url);
    const pathname = url.pathname;
    if (request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();
      const session = {
        webSocket: server,
        id: crypto.randomUUID()
      };
      this.sessions.set(session.id, session);
      server.addEventListener("message", async (event) => {
        await this.handleWebSocketMessage(session, event.data);
      });
      server.addEventListener("close", () => {
        this.handleWebSocketClose(session);
      });
      server.addEventListener("error", (error) => {
        this.handleWebSocketError(session, error);
      });
      server.send(JSON.stringify({
        type: "connected",
        timestamp: (/* @__PURE__ */ new Date()).toISOString()
      }));
      return new Response(null, {
        status: 101,
        webSocket: client
      });
    }
    if (pathname === "/initialize") {
      const data = await request.json();
      for (const [key, value] of Object.entries(data)) {
        await this.storage.put(key, value);
      }
      return new Response(JSON.stringify({ status: "initialized" }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    if (pathname.startsWith("/method/")) {
      const method = pathname.slice("/method/".length);
      const params = await request.json();
      let result;
      switch (method) {
        case "echo":
          result = params;
          break;
        case "increment":
          const counterKey = params.key || "counter";
          const increment = params.increment || 1;
          const currentValue = await this.storage.get(counterKey) || 0;
          const newValue = currentValue + increment;
          await this.storage.put(counterKey, newValue);
          result = { [counterKey]: newValue };
          break;
        case "set_multiple":
          if (params.keys && typeof params.keys === "object") {
            await Promise.all(
              Object.entries(params.keys).map(
                ([key, value]) => this.storage.put(key, value)
              )
            );
            result = { status: "success", count: Object.keys(params.keys).length };
          } else {
            return new Response(JSON.stringify({ error: "Invalid keys parameter" }), {
              status: 400,
              headers: { "Content-Type": "application/json" }
            });
          }
          break;
        default:
          return new Response(JSON.stringify({ error: "Method not found" }), {
            status: 404,
            headers: { "Content-Type": "application/json" }
          });
      }
      return new Response(JSON.stringify(result), {
        headers: { "Content-Type": "application/json" }
      });
    }
    if (pathname.startsWith("/state")) {
      const parts = pathname.split("/");
      const key = parts.length > 2 ? parts[2] : null;
      if (key) {
        const value = await this.storage.get(key);
        if (value === void 0) {
          return new Response(JSON.stringify({ error: "Key not found" }), {
            status: 404,
            headers: { "Content-Type": "application/json" }
          });
        }
        return new Response(JSON.stringify({ [key]: value }), {
          headers: { "Content-Type": "application/json" }
        });
      } else {
        const keys = await this.storage.list();
        const state = {};
        for (const [key2, value] of keys) {
          state[key2] = value;
        }
        return new Response(JSON.stringify(state), {
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    if (request.method === "PUT" && pathname.startsWith("/state/")) {
      const key = pathname.slice("/state/".length);
      try {
        const body = await request.json();
        const value = body.value;
        await this.storage.put(key, value);
        return new Response(JSON.stringify({ status: "updated", key }), {
          headers: { "Content-Type": "application/json" }
        });
      } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    if (request.method === "DELETE" && pathname.startsWith("/state/")) {
      const key = pathname.slice("/state/".length);
      await this.storage.delete(key);
      return new Response(JSON.stringify({ status: "deleted", key }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    return new Response(JSON.stringify({ error: "Not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" }
    });
  }
  // WebSocket handlers
  async handleWebSocketMessage(session, message) {
    try {
      const data = JSON.parse(message);
      switch (data.type) {
        case "echo":
          session.webSocket.send(JSON.stringify({
            type: "echo_response",
            id: data.id,
            data: data.data,
            timestamp: (/* @__PURE__ */ new Date()).toISOString()
          }));
          break;
        case "get":
          const value = await this.storage.get(data.key);
          session.webSocket.send(JSON.stringify({
            type: "get_response",
            id: data.id,
            key: data.key,
            value,
            timestamp: (/* @__PURE__ */ new Date()).toISOString()
          }));
          break;
        case "set":
          await this.storage.put(data.key, data.value);
          session.webSocket.send(JSON.stringify({
            type: "set_response",
            id: data.id,
            key: data.key,
            status: "success",
            timestamp: (/* @__PURE__ */ new Date()).toISOString()
          }));
          break;
        default:
          session.webSocket.send(JSON.stringify({
            type: "error",
            error: "Unknown message type",
            timestamp: (/* @__PURE__ */ new Date()).toISOString()
          }));
      }
    } catch (error) {
      session.webSocket.send(JSON.stringify({
        type: "error",
        error: error.message,
        timestamp: (/* @__PURE__ */ new Date()).toISOString()
      }));
    }
  }
  handleWebSocketClose(session) {
    this.sessions.delete(session.id);
  }
  handleWebSocketError(session, error) {
    console.error("WebSocket error:", error);
    this.sessions.delete(session.id);
  }
};
__name(BenchmarkDurableObject, "BenchmarkDurableObject");
var benchmark_worker_default = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.split("/");
    let id;
    if (path[1] === "id" && path.length > 2) {
      id = env.BENCHMARK.idFromString(path[2]);
    } else if (path[1] === "name" && path.length > 2) {
      id = env.BENCHMARK.idFromName(path[2]);
    } else {
      id = env.BENCHMARK.idFromName("default");
    }
    const obj = env.BENCHMARK.get(id);
    const newUrl = new URL(request.url);
    newUrl.pathname = "/" + path.slice(path[1] === "id" || path[1] === "name" ? 3 : 1).join("/");
    const newRequest = new Request(newUrl.toString(), request);
    return obj.fetch(newRequest);
  }
};

// node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    return Response.json(error, {
      status: 500,
      headers: { "MF-Experimental-Error-Stack": "true" }
    });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-xtvoLe/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = benchmark_worker_default;

// node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-xtvoLe/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof __Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
__name(__Facade_ScheduledController__, "__Facade_ScheduledController__");
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = (request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    };
    #dispatcher = (type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    };
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  BenchmarkDurableObject,
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=benchmark_worker.js.map
