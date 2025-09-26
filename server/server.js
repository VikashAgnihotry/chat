const express = require('express');
const http = require('http');
const { Server } = require("socket.io");

const PORT = process.env.PORT || 3000;

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    maxHttpBufferSize: 1e7, // Set limit to 10 MB
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// A simple in-memory store to map user IDs to their socket IDs
const users = {};
const offlineMessages = {}; // Add this line

app.get('/', (req, res) => {
    res.send('<h1>Secure Chat Server</h1><p>Server is running and listening for WebSocket connections.</p>');
});

io.on('connection', (socket) => {
    console.log(`A user connected with socket ID: ${socket.id}`);

    // When a user registers, store their userId and socket.id
    socket.on('register_user', (userId) => {
        users[userId] = socket.id;
        console.log(`User registered: ${userId} with socket ID: ${socket.id}`);
        console.log('Current users:', users);

        // Add this block to check for and send offline messages
        if (offlineMessages[userId]) {
            console.log(`Sending ${offlineMessages[userId].length} offline messages to ${userId}`);
            offlineMessages[userId].forEach(msg => {
                socket.emit('receive_message', msg);
            });
            // Clear the messages after sending
            delete offlineMessages[userId];
        }
    });

    // Listen for private messages
    socket.on('chat_message', (msg) => {
        console.log(`Message from ${msg.senderId} to ${msg.recipientId}: ${msg.text}`);
        
        const recipientSocketId = users[msg.recipientId];
        if (recipientSocketId) {
            // Send the message directly to the recipient's socket
            io.to(recipientSocketId).emit('receive_message', msg);
            console.log(`Message relayed to socket: ${recipientSocketId}`);
        } else {
            // Replace the old console.log with this block to store messages
            console.log(`Recipient ${msg.recipientId} not found or offline. Storing message.`);
            if (!offlineMessages[msg.recipientId]) {
                offlineMessages[msg.recipientId] = [];
            }
            offlineMessages[msg.recipientId].push(msg);
            console.log('Current offline messages:', offlineMessages);
        }
    });

    socket.on('disconnect', () => {
        console.log(`User with socket ID: ${socket.id} disconnected.`);
        // Find and remove the user from our list on disconnect
        for (const userId in users) {
            if (users[userId] === socket.id) {
                delete users[userId];
                console.log(`Unregistered user: ${userId}`);
                break;
            }
        }
        console.log('Current users:', users);
    });
});

server.listen(PORT, () => {
    console.log(`Server is running on http://localhost:${PORT}`);
});


