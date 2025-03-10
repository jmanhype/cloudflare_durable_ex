/**
 * CloudflareDurable Durable Objects Worker
 * 
 * This Cloudflare Worker script provides a generic interface for interacting with 
 * Durable Objects from Elixir applications, supporting HTTP and WebSocket APIs.
 */

// Define the Durable Object class
export class DurableObject {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.storage = state.storage;
    this.sessions = new Map(); // WebSocket sessions
  }

  // Handle HTTP requests
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    console.log(`Durable Object received request: ${request.method} ${path}`);
    
    try {
      // Route based on HTTP method
      if (request.method === "GET") {
        return await this.handleGet(path);
      } else if (request.method === "POST") {
        const data = await request.json();
        console.log(`POST data: ${JSON.stringify(data)}`);
        return await this.handlePost(path, data);
      } else if (request.method === "PUT") {
        const data = await request.json();
        console.log(`PUT data: ${JSON.stringify(data)}`);
        return await this.handlePut(path, data);
      } else if (request.method === "DELETE") {
        return await this.handleDelete(path);
      } else {
        return new Response("Method not allowed", { status: 405 });
      }
    } catch (error) {
      console.error(`Error in Durable Object: ${error.stack || error}`);
      return new Response(`Error: ${error.message}`, { status: 500 });
    }
  }

  // Handle GET requests
  async handleGet(path) {
    console.log(`Handling GET request for path: ${path}`);
    // Get state or specific key
    if (path === "/state") {
      const data = await this.storage.list();
      return new Response(JSON.stringify({ data }), {
        headers: { "Content-Type": "application/json" }
      });
    } else if (path.startsWith("/state/")) {
      const key = path.substring(7);
      const value = await this.storage.get(key);
      
      if (value === undefined) {
        return new Response("Key not found", { status: 404 });
      }
      
      return new Response(JSON.stringify({ key, value }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle POST requests
  async handlePost(path, data) {
    console.log(`Handling POST request for path: ${path}`);
    
    // Handle initialization
    if (path === "/initialize") {
      console.log("Processing initialization request");
      
      // Store the initial data
      for (const [key, value] of Object.entries(data)) {
        await this.storage.put(key, value);
        console.log(`Stored ${key}: ${JSON.stringify(value)}`);
      }
      
      return new Response(JSON.stringify({ success: true }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    // Custom method calls
    if (path.startsWith("/method/")) {
      const method = path.substring(8);
      console.log(`Calling method: ${method}`);
      
      // Check if the method exists
      const methodName = `method_${method}`;
      if (typeof this[methodName] !== "function") {
        console.log(`Method not found: ${methodName}`);
        return new Response(`Method not found: ${method}`, { status: 404 });
      }
      
      // Call the method
      try {
        const result = await this[methodName](data);
        console.log(`Method result: ${JSON.stringify(result)}`);
        return new Response(JSON.stringify({ result }), {
          headers: { "Content-Type": "application/json" }
        });
      } catch (error) {
        console.error(`Error calling method ${method}: ${error.stack || error}`);
        return new Response(`Error calling method: ${error.message}`, { status: 500 });
      }
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle PUT requests
  async handlePut(path, data) {
    // Update state
    if (path.startsWith("/state/")) {
      const key = path.substring(7);
      
      await this.storage.put(key, data.value);
      
      // Notify connected clients
      this.broadcastUpdate(key, data.value);
      
      return new Response(JSON.stringify({ success: true, key }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle DELETE requests
  async handleDelete(path) {
    // Delete state
    if (path.startsWith("/state/")) {
      const key = path.substring(7);
      
      await this.storage.delete(key);
      
      // Notify connected clients
      this.broadcastUpdate(key, null);
      
      return new Response(JSON.stringify({ success: true, key }), {
        headers: { "Content-Type": "application/json" }
      });
    }
    
    return new Response("Not found", { status: 404 });
  }

  // Handle WebSocket connections
  async handleWebSocketUpgrade(request) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    
    // Accept the WebSocket connection
    server.accept();
    
    // Generate a session ID
    const sessionId = crypto.randomUUID();
    
    // Store the WebSocket
    this.sessions.set(sessionId, server);
    
    // Set up event handlers
    server.addEventListener("message", async event => {
      try {
        const message = JSON.parse(event.data);
        
        // Handle different message types
        if (message.type === "method") {
          // Call a method on this class
          if (typeof this[message.method] === "function" && message.method.startsWith("method_")) {
            try {
              const result = await this[message.method](message.params);
              server.send(JSON.stringify({
                type: "response",
                id: message.id,
                success: true,
                result
              }));
            } catch (error) {
              server.send(JSON.stringify({
                type: "response",
                id: message.id,
                success: false,
                error: error.message
              }));
            }
          } else {
            server.send(JSON.stringify({
              type: "response",
              id: message.id,
              success: false,
              error: "Method not found"
            }));
          }
        }
      } catch (error) {
        console.error("Error handling WebSocket message:", error);
        server.send(JSON.stringify({
          type: "error",
          error: "Failed to process message"
        }));
      }
    });
    
    // Handle WebSocket close
    server.addEventListener("close", () => {
      this.sessions.delete(sessionId);
    });
    
    // Handle WebSocket error
    server.addEventListener("error", () => {
      this.sessions.delete(sessionId);
    });
    
    // Send initial state
    const data = await this.storage.list();
    server.send(JSON.stringify({
      type: "init",
      state: data
    }));
    
    return new Response(null, {
      status: 101,
      webSocket: client
    });
  }

  // Broadcast an update to all connected WebSocket clients
  broadcastUpdate(key, value) {
    const update = JSON.stringify({
      type: "update",
      key,
      value,
      timestamp: new Date().toISOString()
    });
    
    for (const client of this.sessions.values()) {
      client.send(update);
    }
  }

  // Custom methods that can be called via HTTP or WebSocket

  // Example method: echo
  async method_echo(data) {
    console.log(`Echo method called with data: ${JSON.stringify(data)}`);
    return data;
  }

  // Example method: increment counter
  async method_increment(data) {
    console.log(`Incrementing counter with data: ${JSON.stringify(data)}`);
    const increment = data.increment || 1;
    
    // Get current value
    let value = await this.storage.get("value") || 0;
    console.log(`Current value: ${value}`);
    
    // Increment value
    value = Number(value) + increment;
    console.log(`New value: ${value}`);
    
    // Store new value
    await this.storage.put("value", value);
    
    // Return new value
    return { value };
  }
  
  // Example method: update document
  async method_update(data) {
    if (!data.content) {
      throw new Error("Content is required");
    }
    
    // Get current document state
    let doc = await this.storage.get("document") || {
      content: "",
      version: 0,
      lastModified: new Date().toISOString()
    };
    
    // Update document
    doc.content = data.content;
    doc.version = (doc.version || 0) + 1;
    doc.lastModified = new Date().toISOString();
    
    // Store updated document
    await this.storage.put("document", doc);
    
    // Notify connected clients
    this.broadcastUpdate("document", doc);
    
    return doc;
  }
}

// Main Worker script
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    console.log(`Worker received request: ${request.method} ${path}`);
    
    // Route requests to appropriate Durable Object
    if (path.startsWith("/object/")) {
      // Extract object ID from path
      const parts = path.split("/");
      if (parts.length < 3) {
        console.log("Invalid object ID path format");
        return new Response("Invalid object ID", { status: 400 });
      }
      
      const objectId = parts[2];
      console.log(`Routing to Durable Object with ID: ${objectId}`);
      
      // Construct a stub for the Durable Object
      const objectStub = env.DURABLE_OBJECT.get(env.DURABLE_OBJECT.idFromName(objectId));
      
      // Remove /object/{id} prefix from path
      const newUrl = new URL(request.url);
      newUrl.pathname = "/" + parts.slice(3).join("/");
      console.log(`Forwarding to DO with new path: ${newUrl.pathname}`);
      
      // Forward the request to the Durable Object
      const newRequest = new Request(newUrl, request);
      return objectStub.fetch(newRequest);
    }
    
    // Initialize a new Durable Object
    if (path.startsWith("/initialize/")) {
      console.log("Initialize endpoint called");
      const objectId = path.substring(12);
      console.log(`Initializing object with ID: ${objectId}`);
      
      if (request.method !== "POST") {
        console.log(`Method not allowed: ${request.method}`);
        return new Response("Method not allowed", { status: 405 });
      }
      
      try {
        // Parse the request body
        const data = await request.json();
        console.log(`Initialization data: ${JSON.stringify(data)}`);
        
        // Get a stub for the Durable Object
        const objectStub = env.DURABLE_OBJECT.get(env.DURABLE_OBJECT.idFromName(objectId));
        
        // Forward the initialization request to the Durable Object
        const doRequest = new Request(new URL("/initialize", request.url), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(data)
        });
        
        console.log("Forwarding initialization to Durable Object");
        const response = await objectStub.fetch(doRequest);
        
        // Return the response from the Durable Object
        const responseText = await response.text();
        console.log(`Initialization response: ${responseText}`);
        
        return new Response(responseText, {
          status: response.status,
          headers: { "Content-Type": "application/json" }
        });
      } catch (error) {
        console.error(`Error initializing Durable Object: ${error.stack || error}`);
        return new Response(`Error initializing Durable Object: ${error.message}`, { 
          status: 500,
          headers: { "Content-Type": "application/json" }
        });
      }
    }
    
    console.log(`No matching route for path: ${path}`);
    return new Response("Not found", { status: 404 });
  }
}; 