/**
 * Phoenix Channel client for Cloudflare Durable Objects
 * 
 * This module provides a JavaScript client for interacting with
 * Cloudflare Durable Objects through Phoenix Channels.
 */

import {Socket} from "phoenix"

/**
 * Creates a client for interacting with Durable Objects via Phoenix Channels.
 * 
 * @param {Object} options - Configuration options
 * @param {String} options.socketUrl - URL for the Phoenix socket (default: "/socket")
 * @param {Object} options.socketParams - Parameters to pass when connecting the socket
 * @param {Function} options.onConnectError - Callback for socket connection errors
 * @returns {Object} - The Durable Objects client interface
 */
export function createDurableClient(options = {}) {
  const socketUrl = options.socketUrl || "/socket"
  const socketParams = options.socketParams || {}
  
  // Initialize the Phoenix Socket
  const socket = new Socket(socketUrl, {params: socketParams})
  socket.connect()
  
  // Track active connections
  const connections = new Map()
  
  // Handle socket errors
  socket.onError((error) => {
    console.error("Durable Objects socket error:", error)
    if (options.onConnectError) {
      options.onConnectError(error)
    }
  })
  
  return {
    /**
     * Connects to a Durable Object via Phoenix Channels.
     * 
     * @param {String} objectId - The ID of the Durable Object
     * @param {Object} callbacks - Callback functions for events
     * @param {Function} callbacks.onJoin - Called when successfully joined
     * @param {Function} callbacks.onError - Called on error
     * @param {Function} callbacks.onUpdate - Called when state is updated
     * @returns {Object} - Connection interface with methods for interacting with the DO
     */
    connect(objectId, callbacks = {}) {
      if (connections.has(objectId)) {
        return connections.get(objectId)
      }
      
      const channel = socket.channel(`durable_object:${objectId}`, {})
      
      // Set up event callbacks
      channel.on("state_updated", (update) => {
        console.debug(`Durable Object ${objectId} updated:`, update)
        if (callbacks.onUpdate) {
          callbacks.onUpdate(update)
        }
      })
      
      // Join the channel
      channel.join()
        .receive("ok", (resp) => {
          console.debug(`Joined Durable Object ${objectId}:`, resp)
          if (callbacks.onJoin) {
            callbacks.onJoin(resp)
          }
        })
        .receive("error", (resp) => {
          console.error(`Error joining Durable Object ${objectId}:`, resp)
          if (callbacks.onError) {
            callbacks.onError(resp)
          }
        })
      
      // Create the connection interface
      const connection = {
        channel,
        
        /**
         * Updates state in the Durable Object.
         * 
         * @param {String} key - The key to update
         * @param {*} value - The value to set
         * @returns {Promise} - Resolves when the update is complete
         */
        updateState(key, value) {
          return new Promise((resolve, reject) => {
            channel.push("update_state", {key, value})
              .receive("ok", resolve)
              .receive("error", reject)
          })
        },
        
        /**
         * Calls a method on the Durable Object.
         * 
         * @param {String} method - The method to call
         * @param {Object} params - Parameters to pass to the method
         * @returns {Promise} - Resolves with the result of the method call
         */
        callMethod(method, params = {}) {
          return new Promise((resolve, reject) => {
            channel.push("call_method", {method, params})
              .receive("ok", resolve)
              .receive("error", reject)
          })
        },
        
        /**
         * Refreshes the Durable Object state.
         * 
         * @returns {Promise} - Resolves when the refresh is complete
         */
        refresh() {
          return new Promise((resolve, reject) => {
            channel.push("refresh_state", {})
              .receive("ok", resolve)
              .receive("error", reject)
          })
        },
        
        /**
         * Leaves the Durable Object channel.
         */
        disconnect() {
          channel.leave()
          connections.delete(objectId)
        }
      }
      
      connections.set(objectId, connection)
      return connection
    },
    
    /**
     * Disconnects from a Durable Object.
     * 
     * @param {String} objectId - The ID of the Durable Object to disconnect from
     */
    disconnect(objectId) {
      const connection = connections.get(objectId)
      if (connection) {
        connection.disconnect()
      }
    },
    
    /**
     * Disconnects from all Durable Objects.
     */
    disconnectAll() {
      for (const connection of connections.values()) {
        connection.disconnect()
      }
    },
    
    /**
     * Gets the Phoenix Socket instance.
     * 
     * @returns {Socket} - The Phoenix Socket
     */
    getSocket() {
      return socket
    }
  }
}

// Example usage:
// 
// const client = createDurableClient({
//   socketParams: { token: "user-auth-token" }
// })
// 
// const counter = client.connect("counter-123", {
//   onUpdate: (state) => {
//     console.log("Counter updated:", state)
//     document.getElementById("counter-value").textContent = state.value || 0
//   }
// })
// 
// // Increment the counter
// counter.updateState("value", 42)
// 
// // Call a method
// counter.callMethod("increment", { amount: 5 })
//   .then(result => console.log("Counter incremented:", result))
//
// // Disconnect when done
// counter.disconnect() 