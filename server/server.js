// A simple Node.js server using Express and Socket.IO for our chat app

const express = require('express');
const http = require('http');
const { Server } = require("socket.io");

const PORT = process.env.PORT || 3000;

// Set up the server
const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*", // Allow all origins for simplicity in development
        methods: ["GET", "POST"]
    }
});

app.get('/', (req, res) => {
    res.send('<h1>Secure Chat Server</h1><p>Server is running and listening for WebSocket connections.</p>');
});

// Listen for new connections
io.on('connection', (socket) => {
    console.log(`A user connected with socket ID: ${socket.id}`);

    // Handle user disconnection
    socket.on('disconnect', () => {
        console.log(`User with socket ID: ${socket.id} disconnected.`);
    });

    // Listen for a 'chat_message' event from a client
    socket.on('chat_message', (msg) => {
        console.log(`Message received from ${socket.id}: ${msg.text}`);
        
        // For now, broadcast the message to all other connected clients.
        // In the future, this will be directed to a specific recipient.
        socket.broadcast.emit('receive_message', msg);
    });

    // You can add more event listeners here for things like:
    // - joining a specific chat room
    // - typing indicators
    // - user authentication
});

// Start the server
server.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});
