// الإشعارات اللحظية: أول ما طلب يتسجل يوصل للفرع فوراً
const { Server } = require('socket.io');
const { userFromToken, can } = require('./auth');

let io = null;

function init(httpServer) {
  io = new Server(httpServer, { cors: { origin: '*' } });

  io.use((socket, next) => {
    const user = userFromToken(socket.handshake.auth && socket.handshake.auth.token);
    if (!user) return next(new Error('unauthorized'));
    socket.data.user = user;
    next();
  });

  io.on('connection', (socket) => {
    const u = socket.data.user;
    socket.join(`user:${u.id}`);
    if (can(u, 'orders.view_all')) socket.join('all');
    if (u.branch_id && can(u, 'orders.view_branch')) socket.join(`branch:${u.branch_id}`);
  });

  return io;
}

// إرسال حدث الطلب لكل اللي يخصهم (الفرع، الإدارة، الطيار، اللي سجل الطلب)
function emitOrder(event, order, extraRooms = []) {
  if (!io || !order) return;
  const rooms = ['all', `branch:${order.branch_id}`, ...extraRooms];
  if (order.driver_id) rooms.push(`user:${order.driver_id}`);
  if (order.created_by) rooms.push(`user:${order.created_by}`);
  io.to(rooms).emit(event, order);
}

function emitAll(event, payload) {
  if (io) io.emit(event, payload);
}

module.exports = { init, emitOrder, emitAll };
