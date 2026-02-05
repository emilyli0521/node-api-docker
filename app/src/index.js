const express = require('express');

const app = express();

app.get('/', (req, res) => {
  res.status(200).send('OK\n');
});

const server = app.listen(3000, () => {
  console.log('Server listening on port 3000');
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => process.exit(0));
});
