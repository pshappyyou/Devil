// var express = require('express');
// var router = express.Router();

// /* GET home page. */
// router.get('/', function(req, res, next) {
//   console.log('I am index router. I will emit the socket now!')
//   res.io.emit("fromRouter", "gogogo!");
//   res.io.emit("mydata", 'hohoho');
//   res.render('index', { title: 'Team Chat', yoyoyo: 'Test', s_time: new Date().getTime() });
//   // res.send('respond with a resource.');
// });

// module.exports = router;
// routes/index.js
const router = require('express').Router();
const r = require('rethinkdb');

let connection;
r.connect({host: '10.108.8.108', port: 28015, db: 'DevilCASE'})
    .then(conn => {
      connection = conn;
    });

/* Render the feed. */
router.get('/', async (req, res, next) => {
  const posts = await r.table('posts').orderBy(r.desc('date')).run(connection)
      .then(cursor => cursor.toArray());
  res.render('index', { posts });
});

module.exports = router;