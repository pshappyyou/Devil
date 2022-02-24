// var createError = require('http-errors');
// var express = require('express');
// var path = require('path');
// var cookieParser = require('cookie-parser');
// var logger = require('morgan');
// var socketio = require('socket.io');

// // Routings
// var indexRouter = require('./routes/index');
// var usersRouter = require('./routes/users');
// var casesRouter = require('./routes/newcases');

// // Create Express App
// var app = express();

// // Create the http server 
// const server = require('http').createServer(app);
  
// // Create the Socket IO server on  
// // the top of http server 
// // 서버 소켓 - 소켓 이름은 io (클라이언트 소켓 하고 헷깔리지 말것)
// // on: input from client
// // emit: output to client
// const io = socketio(server);

// app.use(function(req, res, next) {
//   res.io = io;
//   next();
// });

// // This is Server Socket!
// io.on("connection", function(socket){
//   // Server console.log is output to terminal window.
//   console.log("A User CONNECTted");
//   // socket.emit('news', { hello: 'world' });
//   // socket.username = 'jchoiii';
//   socket.on('change_username', (data) => {
//     socket.username = data.username;
//   });

//   socket.on('new message', function(msg){
//     console.log('new message:' + msg);
//     io.emit('chat message', msg);
//   });
  
//   io.emit('socketToMe', 'from app.js'); // Server to Client directly pass data
// });

// // view engine setup
// app.set('views', path.join(__dirname, 'views'));
// app.set('view engine', 'ejs');

// app.use(logger('dev'));
// app.use(express.json());
// app.use(express.urlencoded({ extended: false }));
// app.use(cookieParser());
// app.use(express.static(path.join(__dirname, 'public')));

// app.use('/', indexRouter);
// app.use('/users', usersRouter);
// app.use('/cases', casesRouter);
// app.use('/newcases', casesRouter);

// // catch 404 and forward to error handler
// app.use(function(req, res, next) {
//   next(createError(404));
// });

// // error handler
// app.use(function(err, req, res, next) {
//   // set locals, only providing error in development
//   res.locals.message = err.message;
//   res.locals.error = req.app.get('env') === 'development' ? err : {};

//   // render the error page
//   res.status(err.status || 500);
//   res.render('error');
// });

// module.exports = { app: app, server: server };


 // app.js
 require('dotenv').config();
 const express = require('express');
 const path = require('path');
 const logger = require('morgan');
 const cookieParser = require('cookie-parser');
 
 const app = express();
 
 // view engine setup
 app.set('views', path.join(__dirname, 'views'));
 app.set('view engine', 'hbs');
 
 app.use(logger('dev'));
 app.use(express.json());
 app.use(express.urlencoded({ extended: false }));
 app.use(cookieParser());
 app.use(express.static(path.join(__dirname, 'public')));

 app.use('/', require('./routes/index'));
 
 // error handler
 app.use((err, req, res, next) => {
   res.locals.message = err.message;
   res.locals.error = err;
 
   // render the error page
   res.status(err.status || 500);
   res.render('error');
 });
 
 module.exports = app;