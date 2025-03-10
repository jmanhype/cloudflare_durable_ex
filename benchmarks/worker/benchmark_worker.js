// This Cloudflare Worker implements a Durable Object for benchmarking purposes

export class BenchmarkDurableObject {
  constructor(state, env) {
    this.state = state;
    this.storage = state.storage;
    
    // WebSocket sessions
    this.sessions = new Map();
  }
  
  // Handle HTTP requests
  async fetch(request) {
    const url = new URL(request.url);
    const pathname = url.pathname;
    
    // Handle WebSocket upgrade requests
    if (request.headers.get('Upgrade') === 'websocket') {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      
      // Set up WebSocket handlers
      server.accept();
      
      const session = {
        webSocket: server,
        id: crypto.randomUUID(),
      };
      
      this.sessions.set(session.id, session);
      
      // Handle messages from the client
      server.addEventListener('message', async (event) => {
        await this.handleWebSocketMessage(session, event.data);
      });

      // Handle WebSocket closing
      server.addEventListener('close', () => {
        this.handleWebSocketClose(session);
      });

      // Handle WebSocket errors
      server.addEventListener('error', (error) => {
        this.handleWebSocketError(session, error);
      });
      
      // Send initial connection message
      server.send(JSON.stringify({
        type: 'connected',
        timestamp: new Date().toISOString()
      }));
      
      return new Response(null, {
        status: 101,
        webSocket: client,
      });
    }
    
    // Initialize the object
    if (pathname === '/initialize') {
      const data = await request.json();
      
      // Store all keys from the request body
      for (const [key, value] of Object.entries(data)) {
        await this.storage.put(key, value);
      }
      
      return new Response(JSON.stringify({ status: 'initialized' }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Call method endpoint
    if (pathname.startsWith('/method/')) {
      const method = pathname.slice('/method/'.length);
      const params = await request.json();
      
      let result;
      
      // Handle different methods
      switch (method) {
        case 'echo':
          // Echo back the received parameters
          result = params;
          break;
          
        case 'increment':
          // Increment a counter
          const counterKey = params.key || 'counter';
          const increment = params.increment || 1;
          
          const currentValue = await this.storage.get(counterKey) || 0;
          const newValue = currentValue + increment;
          
          await this.storage.put(counterKey, newValue);
          
          result = { [counterKey]: newValue };
          break;
          
        case 'set_multiple':
          // Set multiple keys at once
          if (params.keys && typeof params.keys === 'object') {
            await Promise.all(
              Object.entries(params.keys).map(([key, value]) => 
                this.storage.put(key, value)
              )
            );
            
            result = { status: 'success', count: Object.keys(params.keys).length };
          } else {
            return new Response(JSON.stringify({ error: 'Invalid keys parameter' }), {
              status: 400,
              headers: { 'Content-Type': 'application/json' }
            });
          }
          break;
          
        default:
          return new Response(JSON.stringify({ error: 'Method not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          });
      }
      
      return new Response(JSON.stringify(result), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Get state endpoint
    if (pathname.startsWith('/state')) {
      // Check if we're requesting a specific key
      const parts = pathname.split('/');
      const key = parts.length > 2 ? parts[2] : null;
      
      if (key) {
        // Get a specific key
        const value = await this.storage.get(key);
        
        if (value === undefined) {
          return new Response(JSON.stringify({ error: 'Key not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        
        return new Response(JSON.stringify({ [key]: value }), {
          headers: { 'Content-Type': 'application/json' }
        });
      } else {
        // Get all state
        const keys = await this.storage.list();
        const state = {};
        
        for (const [key, value] of keys) {
          state[key] = value;
        }
        
        return new Response(JSON.stringify(state), {
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }
    
    // Update state endpoint (PUT /state/:key)
    if (request.method === 'PUT' && pathname.startsWith('/state/')) {
      const key = pathname.slice('/state/'.length);
      
      try {
        const body = await request.json();
        const value = body.value;
        
        await this.storage.put(key, value);
        
        return new Response(JSON.stringify({ status: 'updated', key }), {
          headers: { 'Content-Type': 'application/json' }
        });
      } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        });
      }
    }
    
    // Delete state endpoint (DELETE /state/:key)
    if (request.method === 'DELETE' && pathname.startsWith('/state/')) {
      const key = pathname.slice('/state/'.length);
      
      await this.storage.delete(key);
      
      return new Response(JSON.stringify({ status: 'deleted', key }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Default: Not found
    return new Response(JSON.stringify({ error: 'Not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  // WebSocket handlers
  
  async handleWebSocketMessage(session, message) {
    try {
      const data = JSON.parse(message);
      
      // Handle different message types
      switch (data.type) {
        case 'echo':
          // Echo the message back with the same ID
          session.webSocket.send(JSON.stringify({
            type: 'echo_response',
            id: data.id,
            data: data.data,
            timestamp: new Date().toISOString()
          }));
          break;
          
        case 'get':
          // Get a value from storage
          const value = await this.storage.get(data.key);
          session.webSocket.send(JSON.stringify({
            type: 'get_response',
            id: data.id,
            key: data.key,
            value: value,
            timestamp: new Date().toISOString()
          }));
          break;
          
        case 'set':
          // Set a value in storage
          await this.storage.put(data.key, data.value);
          session.webSocket.send(JSON.stringify({
            type: 'set_response',
            id: data.id,
            key: data.key,
            status: 'success',
            timestamp: new Date().toISOString()
          }));
          break;
          
        default:
          session.webSocket.send(JSON.stringify({
            type: 'error',
            error: 'Unknown message type',
            timestamp: new Date().toISOString()
          }));
      }
    } catch (error) {
      session.webSocket.send(JSON.stringify({
        type: 'error',
        error: error.message,
        timestamp: new Date().toISOString()
      }));
    }
  }
  
  handleWebSocketClose(session) {
    // Remove the session
    this.sessions.delete(session.id);
  }
  
  handleWebSocketError(session, error) {
    // Log the error
    console.error('WebSocket error:', error);
    
    // Remove the session
    this.sessions.delete(session.id);
  }
}

// Worker code
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.split('/');
    
    // Get the object ID from the URL (either directly specified or generate from name)
    let id;
    if (path[1] === 'id' && path.length > 2) {
      // Direct ID: /id/...
      id = env.BENCHMARK.idFromString(path[2]);
    } else if (path[1] === 'name' && path.length > 2) {
      // Name-based ID: /name/...
      id = env.BENCHMARK.idFromName(path[2]);
    } else {
      // Default to a root object
      id = env.BENCHMARK.idFromName('default');
    }
    
    // Get the Durable Object stub
    const obj = env.BENCHMARK.get(id);
    
    // Remove the ID/name part from the URL
    const newUrl = new URL(request.url);
    newUrl.pathname = '/' + path.slice(path[1] === 'id' || path[1] === 'name' ? 3 : 1).join('/');
    
    // Forward the modified request to the Durable Object
    const newRequest = new Request(newUrl.toString(), request);
    return obj.fetch(newRequest);
  }
} 