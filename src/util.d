import std.base64;
import std.conv;
import std.digest.crc, std.digest.sha;
import std.net.curl;
import std.datetime;
import std.file;
import std.path;
import std.regex;
import std.socket;
import std.stdio;
import std.string;
import qxor;

private string deviceName;

static this()
{
	deviceName = Socket.hostName;
}

// gives a new name to the specified file or directory
void safeRename(const(char)[] path)
{
	auto ext = extension(path);
	auto newPath = path.chomp(ext) ~ "-" ~ deviceName;
	if (exists(newPath ~ ext)) {
		int n = 2;
		char[] newPath2;
		do {
			newPath2 = newPath ~ "-" ~ n.to!string;
			n++;
		} while (exists(newPath2 ~ ext));
		newPath = newPath2;
	}
	newPath ~= ext;
	rename(path, newPath);
}

// deletes the specified file without throwing an exception if it does not exists
void safeRemove(const(char)[] path)
{
	if (exists(path)) remove(path);
}

// returns the crc32 hex string of a file
string computeCrc32(string path)
{
	CRC32 crc;
	auto file = File(path, "rb");
	foreach (ubyte[] data; chunks(file, 4096)) {
		crc.put(data);
	}
	return crc.finish().toHexString().dup;
}

// returns the sha1 hash hex string of a file
string computeSha1Hash(string path)
{
	SHA1 sha;
	auto file = File(path, "rb");
	foreach (ubyte[] data; chunks(file, 4096)) {
		sha.put(data);
	}
	return sha.finish().toHexString().dup;
}

// returns the quickXorHash base64 string of a file
string computeQuickXorHash(string path)
{
	QuickXor qxor;
	auto file = File(path, "rb");
	foreach (ubyte[] data; chunks(file, 4096)) {
		qxor.put(data);
	}
	return Base64.encode(qxor.finish());
}

// converts wildcards (*, ?) to regex
Regex!char wild2regex(const(char)[] pattern)
{
	string str;
	str.reserve(pattern.length + 2);
	str ~= "^";
	foreach (c; pattern) {
		switch (c) {
		case '*':
			str ~= "[^/]*";
			break;
		case '.':
			str ~= "\\.";
			break;
		case '?':
			str ~= "[^/]";
			break;
		case '|':
			str ~= "$|^";
			break;
		default:
			str ~= c;
			break;
		}
	}
	str ~= "$";
	return regex(str, "i");
}

// returns true if the network connection is available
bool testNetwork()
{
	try {
		HTTP http = HTTP("https://login.microsoftonline.com");
		http.dnsTimeout = (dur!"seconds"(5));
		http.method = HTTP.Method.head;
		http.perform();
		return true;
	} catch (SocketException) {
		return false;
	}
}

// calls globMatch for each string in pattern separated by '|'
bool multiGlobMatch(const(char)[] path, const(char)[] pattern)
{
	foreach (glob; pattern.split('|')) {
		if (globMatch!(std.path.CaseSensitive.yes)(path, glob)) {
			return true;
		}
	}
	return false;
}

bool isValidName(string path)
{
	// allow root item
	if (path == ".") {
		return true;
	}

	string itemName = baseName(path);

	// Restriction and limitations about windows naming files
	// https://msdn.microsoft.com/en-us/library/aa365247
	auto invalidNameReg =
		ctRegex!(
			// leading whitespace and trailing whitespace/dot
			`^\s.*|^.*[\s\.]$|` ~
			// invalid character
			`.*[#%<>:"\|\?*/\\].*|` ~
			// reserved device name and trailing .~
			`(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:[.].+)?$`
		);
	auto m = match(itemName, invalidNameReg);

	return m.empty;
}

unittest
{
	assert(multiGlobMatch(".hidden", ".*"));
	assert(multiGlobMatch(".hidden", "file|.*"));
	assert(!multiGlobMatch("foo.bar", "foo|bar"));
	// that should detect invalid file/directory name.
	assert(isValidName("."));
	assert(isValidName("./general.file"));
	assert(!isValidName("./ leading_white_space"));
	assert(!isValidName("./trailing_white_space "));
	assert(!isValidName("./trailing_dot."));
	assert(!isValidName("./includes#in the path"));
	assert(!isValidName("./includes%in the path"));
	assert(!isValidName("./includes<in the path"));
	assert(!isValidName("./includes>in the path"));
	assert(!isValidName("./includes:in the path"));
	assert(!isValidName(`./includes"in the path`));
	assert(!isValidName("./includes|in the path"));
	assert(!isValidName("./includes?in the path"));
	assert(!isValidName("./includes*in the path"));
	assert(!isValidName("./includes / in the path"));
	assert(!isValidName(`./includes\ in the path`));
	assert(!isValidName(`./includes\\ in the path`));
	assert(!isValidName(`./includes\\\\ in the path`));
	assert(!isValidName("./includes\\ in the path"));
	assert(!isValidName("./includes\\\\ in the path"));
	assert(!isValidName("./CON"));
	assert(!isValidName("./CON.text"));
	assert(!isValidName("./PRN"));
	assert(!isValidName("./AUX"));
	assert(!isValidName("./NUL"));
	assert(!isValidName("./COM0"));
	assert(!isValidName("./COM1"));
	assert(!isValidName("./COM2"));
	assert(!isValidName("./COM3"));
	assert(!isValidName("./COM4"));
	assert(!isValidName("./COM5"));
	assert(!isValidName("./COM6"));
	assert(!isValidName("./COM7"));
	assert(!isValidName("./COM8"));
	assert(!isValidName("./COM9"));
	assert(!isValidName("./LPT0"));
	assert(!isValidName("./LPT1"));
	assert(!isValidName("./LPT2"));
	assert(!isValidName("./LPT3"));
	assert(!isValidName("./LPT4"));
	assert(!isValidName("./LPT5"));
	assert(!isValidName("./LPT6"));
	assert(!isValidName("./LPT7"));
	assert(!isValidName("./LPT8"));
	assert(!isValidName("./LPT9"));
}
