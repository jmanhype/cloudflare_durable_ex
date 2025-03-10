// ChatRoom Durable Object implementation

export class ChatRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.storage = state.storage;
    this.sessions = new Map();
    this.messageBuffer = [];
    
    // Set up the system to handle WebSocket connections
    this.state.setWebSocketHandler({
      open: this.handleSessionOpen.bind(this),
      message: this.handleSessionMessage.bind(this),
      close: this.handleSessionClose.bind(this),
      error: this.handleSessionError.bind(this),
    });
  }

  // Called when a new WebSocket connection is established
  async handleSessionOpen(websocket) {
    // Generate a unique ID for this session
    const sessionId = crypto.randomUUID();
    
    // Store the WebSocket connection
    this.sessions.set(sessionId, {
      websocket,
      userId: null,
      username: null,
      joinedAt: new Date().toISOString(),
    });
    
    // Send a welcome message to the new connection
    websocket.send(JSON.stringify({
      type: "system",
      message: "Welcome to the chat room! Please set your username.",
      sessionId,
    }));
    
    // Send recent message history to the new connection
    const messages = await this.getRecentMessages();
    if (messages.length > 0) {
      websocket.send(JSON.stringify({
        type: "history",
        messages,
      }));
    }
    
    // Broadcast user count update to all clients
    this.broadcastUserCount();
  }
  
  // Called when a message is received from a WebSocket
  async handleSessionMessage(websocket, message) {
    // Find the session for this WebSocket
    const sessionId = this.findSessionId(websocket);
    if (!sessionId) return;
    
    const session = this.sessions.get(sessionId);
    
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case "setUsername":
          await this.handleSetUsername(sessionId, session, data.username);
          break;
        
        case "message":
          await this.handleChatMessage(sessionId, session, data.text);
          break;
          
        case "typing":
          await this.broadcastTypingStatus(sessionId, session, data.isTyping);
          break;
      }
    } catch (error) {
      console.error("Error handling message:", error);
      websocket.send(JSON.stringify({
        type: "error",
        message: "Failed to process message: " + error.message,
      }));
    }
  }
  
  // Called when a WebSocket connection is closed
  async handleSessionClose(websocket, code, reason) {
    const sessionId = this.findSessionId(websocket);
    if (!sessionId) return;
    
    const session = this.sessions.get(sessionId);
    this.sessions.delete(sessionId);
    
    // Broadcast user left message if they had set a username
    if (session.username) {
      await this.broadcastSystemMessage(`${session.username} has left the chat`);
    }
    
    // Update user count
    this.broadcastUserCount();
  }
  
  // Called when a WebSocket connection encounters an error
  handleSessionError(websocket, error) {
    console.error("WebSocket error:", error);
  }
  
  // Handle setting a username
  async handleSetUsername(sessionId, session, username) {
    // Validate username
    if (!username || typeof username !== "string" || username.length < 1 || username.length > 32) {
      session.websocket.send(JSON.stringify({
        type: "error",
        message: "Invalid username. Username must be between 1 and 32 characters.",
      }));
      return;
    }
    
    // Check if username is already taken
    for (const [id, s] of this.sessions.entries()) {
      if (id !== sessionId && s.username === username) {
        session.websocket.send(JSON.stringify({
          type: "error",
          message: "Username already taken. Please choose another one.",
        }));
        return;
      }
    }
    
    // Store the old username to check if this is a change
    const oldUsername = session.username;
    
    // Set the username
    session.username = username;
    session.userId = sessionId; // Using sessionId as userId for simplicity
    
    // Send confirmation to the user
    session.websocket.send(JSON.stringify({
      type: "usernameSet",
      username,
      userId: session.userId,
    }));
    
    // If this is a new user joining (not just changing username)
    if (!oldUsername) {
      await this.broadcastSystemMessage(`${username} has joined the chat`);
    } else {
      await this.broadcastSystemMessage(`${oldUsername} changed their name to ${username}`);
    }
    
    // Send updated user list to all clients
    this.broadcastUserList();
  }
  
  // Handle a chat message
  async handleChatMessage(sessionId, session, text) {
    // Ensure the user has set a username
    if (!session.username) {
      session.websocket.send(JSON.stringify({
        type: "error",
        message: "Please set a username before sending messages.",
      }));
      return;
    }
    
    // Validate message
    if (!text || typeof text !== "string" || text.length < 1 || text.length > 1000) {
      session.websocket.send(JSON.stringify({
        type: "error",
        message: "Invalid message. Message must be between 1 and 1000 characters.",
      }));
      return;
    }
    
    // Create message object
    const message = {
      id: crypto.randomUUID(),
      userId: session.userId,
      username: session.username,
      text,
      timestamp: new Date().toISOString(),
    };
    
    // Save message to storage
    await this.saveMessage(message);
    
    // Broadcast message to all clients
    this.broadcastMessage(message);
  }
  
  // Save a message to Durable Object storage
  async saveMessage(message) {
    // Get current messages array
    let messages = await this.storage.get("messages") || [];
    
    // Add new message
    messages.push(message);
    
    // Keep only the last 100 messages
    if (messages.length > 100) {
      messages = messages.slice(messages.length - 100);
    }
    
    // Save back to storage
    await this.storage.put("messages", messages);
  }
  
  // Get recent messages from storage
  async getRecentMessages() {
    const messages = await this.storage.get("messages") || [];
    return messages;
  }
  
  // Broadcast a message to all connected clients
  broadcastMessage(message) {
    const data = JSON.stringify({
      type: "message",
      message,
    });
    
    for (const session of this.sessions.values()) {
      try {
        session.websocket.send(data);
      } catch (error) {
        console.error("Error sending message:", error);
      }
    }
  }
  
  // Broadcast a system message to all connected clients
  async broadcastSystemMessage(text) {
    const message = {
      id: crypto.randomUUID(),
      userId: "system",
      username: "System",
      text,
      timestamp: new Date().toISOString(),
      isSystem: true,
    };
    
    // We don't save system messages to storage
    this.broadcastMessage(message);
  }
  
  // Broadcast typing status to all clients except the sender
  async broadcastTypingStatus(sessionId, session, isTyping) {
    if (!session.username) return;
    
    const data = JSON.stringify({
      type: "typing",
      userId: session.userId,
      username: session.username,
      isTyping,
    });
    
    for (const [id, s] of this.sessions.entries()) {
      if (id !== sessionId) { // Don't send back to the sender
        try {
          s.websocket.send(data);
        } catch (error) {
          console.error("Error sending typing status:", error);
        }
      }
    }
  }
  
  // Broadcast user count to all clients
  broadcastUserCount() {
    const count = Array.from(this.sessions.values()).filter(s => s.username).length;
    
    const data = JSON.stringify({
      type: "userCount",
      count,
    });
    
    for (const session of this.sessions.values()) {
      try {
        session.websocket.send(data);
      } catch (error) {
        console.error("Error sending user count:", error);
      }
    }
  }
  
  // Broadcast the list of connected users to all clients
  broadcastUserList() {
    const users = Array.from(this.sessions.values())
      .filter(s => s.username)
      .map(s => ({
        userId: s.userId,
        username: s.username,
      }));
    
    const data = JSON.stringify({
      type: "userList",
      users,
    });
    
    for (const session of this.sessions.values()) {
      try {
        session.websocket.send(data);
      } catch (error) {
        console.error("Error sending user list:", error);
      }
    }
  }
  
  // Find the session ID for a WebSocket
  findSessionId(websocket) {
    for (const [sessionId, session] of this.sessions.entries()) {
      if (session.websocket === websocket) {
        return sessionId;
      }
    }
    return null;
  }
  
  // Handle HTTP requests (for REST API)
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname.slice(1).split('/');
    
    if (request.method === "GET") {
      // GET /messages - Get recent messages
      if (path[0] === "messages") {
        const messages = await this.getRecentMessages();
        return new Response(JSON.stringify({ messages }), {
          headers: { "Content-Type": "application/json" },
        });
      }
      
      // GET /users - Get active users
      if (path[0] === "users") {
        const users = Array.from(this.sessions.values())
          .filter(s => s.username)
          .map(s => ({
            userId: s.userId,
            username: s.username,
          }));
        
        return new Response(JSON.stringify({ users }), {
          headers: { "Content-Type": "application/json" },
        });
      }
    }
    
    // If path is empty, this is a WebSocket upgrade request
    if (path[0] === "" && request.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      
      // Accept the WebSocket connection
      this.state.acceptWebSocket(pair[1]);
      
      // Return the client end of the WebSocket
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    
    return new Response("Not found", { status: 404 });
  }
}

// Worker script
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.slice(1).split('/');
    
    // Handle the root path - serve basic HTML page
    if (path[0] === "") {
      return new Response(`
        <!DOCTYPE html>
        <html>
        <head>
          <title>Cloudflare Durable Objects Chat</title>
          <style>
            body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
            #messages { height: 400px; overflow-y: scroll; border: 1px solid #ccc; margin-bottom: 10px; padding: 10px; }
            #users { float: right; width: 200px; height: 400px; overflow-y: scroll; border: 1px solid #ccc; padding: 10px; }
            .system { color: #888; font-style: italic; }
            .user-message { margin-bottom: 8px; }
            .username { font-weight: bold; }
            .typing { color: #888; font-style: italic; }
          </style>
        </head>
        <body>
          <h1>Chat Room Example</h1>
          <div id="container">
            <div id="users">
              <h3>Users</h3>
              <div id="user-list"></div>
              <div id="typing-status"></div>
            </div>
            <div id="messages"></div>
          </div>
          <div id="login-form">
            <input type="text" id="username" placeholder="Your username" />
            <button id="set-username">Join Chat</button>
          </div>
          <div id="message-form" style="display: none;">
            <input type="text" id="message" placeholder="Type a message..." />
            <button id="send">Send</button>
          </div>
          
          <script>
            // Connect to the room
            const roomId = new URLSearchParams(window.location.search).get('roomId') || 'default';
            const ws = new WebSocket(\`ws://\${window.location.host}/room/\${roomId}\`);
            
            let sessionId = null;
            let userId = null;
            let username = null;
            
            // Handle WebSocket events
            ws.onopen = (event) => {
              console.log('Connected to the chat room');
            };
            
            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              console.log('Received message:', data);
              
              switch (data.type) {
                case 'system':
                  if (data.sessionId) {
                    sessionId = data.sessionId;
                  }
                  addSystemMessage(data.message);
                  break;
                
                case 'usernameSet':
                  username = data.username;
                  userId = data.userId;
                  document.getElementById('login-form').style.display = 'none';
                  document.getElementById('message-form').style.display = 'block';
                  addSystemMessage('You joined as ' + username);
                  break;
                
                case 'message':
                  addChatMessage(data.message);
                  break;
                
                case 'history':
                  data.messages.forEach(msg => addChatMessage(msg));
                  break;
                
                case 'userList':
                  updateUserList(data.users);
                  break;
                
                case 'typing':
                  updateTypingStatus(data);
                  break;
                
                case 'error':
                  addSystemMessage('Error: ' + data.message);
                  break;
              }
            };
            
            ws.onclose = (event) => {
              addSystemMessage('Disconnected from the chat room');
            };
            
            // Helper functions
            function addSystemMessage(text) {
              const messagesDiv = document.getElementById('messages');
              const messageDiv = document.createElement('div');
              messageDiv.className = 'system';
              messageDiv.textContent = text;
              messagesDiv.appendChild(messageDiv);
              messagesDiv.scrollTop = messagesDiv.scrollHeight;
            }
            
            function addChatMessage(message) {
              const messagesDiv = document.getElementById('messages');
              const messageDiv = document.createElement('div');
              messageDiv.className = 'user-message';
              
              const usernameSpan = document.createElement('span');
              usernameSpan.className = 'username';
              usernameSpan.textContent = message.username + ': ';
              
              const textSpan = document.createElement('span');
              textSpan.className = 'text';
              textSpan.textContent = message.text;
              
              if (message.isSystem) {
                messageDiv.className += ' system';
              }
              
              messageDiv.appendChild(usernameSpan);
              messageDiv.appendChild(textSpan);
              messagesDiv.appendChild(messageDiv);
              messagesDiv.scrollTop = messagesDiv.scrollHeight;
            }
            
            function updateUserList(users) {
              const userListDiv = document.getElementById('user-list');
              userListDiv.innerHTML = '';
              
              users.forEach(user => {
                const userDiv = document.createElement('div');
                userDiv.className = 'user';
                userDiv.textContent = user.username;
                userListDiv.appendChild(userDiv);
              });
            }
            
            function updateTypingStatus(data) {
              const typingStatusDiv = document.getElementById('typing-status');
              
              if (data.isTyping) {
                typingStatusDiv.textContent = data.username + ' is typing...';
              } else {
                typingStatusDiv.textContent = '';
              }
            }
            
            // Set up event listeners
            document.getElementById('set-username').addEventListener('click', () => {
              const usernameInput = document.getElementById('username');
              const username = usernameInput.value.trim();
              if (username) {
                ws.send(JSON.stringify({
                  type: 'setUsername',
                  username,
                }));
              }
            });
            
            document.getElementById('send').addEventListener('click', () => {
              const messageInput = document.getElementById('message');
              const text = messageInput.value.trim();
              if (text) {
                ws.send(JSON.stringify({
                  type: 'message',
                  text,
                }));
                messageInput.value = '';
              }
            });
            
            document.getElementById('message').addEventListener('keypress', (event) => {
              if (event.key === 'Enter') {
                document.getElementById('send').click();
              }
            });
            
            let typingTimeout = null;
            document.getElementById('message').addEventListener('input', () => {
              ws.send(JSON.stringify({
                type: 'typing',
                isTyping: true,
              }));
              
              if (typingTimeout) {
                clearTimeout(typingTimeout);
              }
              
              typingTimeout = setTimeout(() => {
                ws.send(JSON.stringify({
                  type: 'typing',
                  isTyping: false,
                }));
              }, 2000);
            });
          </script>
        </body>
        </html>
      `, {
        headers: {
          'Content-Type': 'text/html',
        },
      });
    }
    
    // Forward request to the appropriate ChatRoom Durable Object
    if (path[0] === "room") {
      const roomId = path[1] || "default";
      const roomObjectId = env.CHATROOM.idFromName(roomId);
      const roomObject = env.CHATROOM.get(roomObjectId);
      
      return roomObject.fetch(request);
    }
    
    return new Response("Not found", { status: 404 });
  }
};

// Declare Durable Object bindings
export { ChatRoom as DurableObject }; 