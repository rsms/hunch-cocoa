var net = require("net");
var stdin = new net.Stream(0, 'unix');
var channelName;
stdin.on('data', function (message) {
  console.log('node: got data on stdin: %j', message.toString('utf8'));
  if (message.toString('utf8') == "exit")
    process.exit(0);
  channelName = message;
});
var siblingIn;
stdin.on('fd', function (fd) {
	if (channelName == "parent") {
		var stream = new net.Stream(fd, "unix");
		//emitter.emit("node", stream);
		stream.resume();
		console.log('node: successfully received fd %d', fd);
		stream.on('data', function (message) {
		  console.log('node: received "'+message+'" on channel "'+channelName+'"');
		  stream.write('pong '+message);
		});
	} else {
		throw new Error("Unknown channel '"+channelName+"'");
	}
});
stdin.resume();

console.log('node: waiting for FD to arrive on stdin');
setTimeout(function(){},500);
