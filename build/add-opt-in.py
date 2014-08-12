#!/usr/bin/env python
# Copyright (c) 2012, Adobe Systems Incorporated
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are
# met:
# 
# * Redistributions of source code must retain the above copyright notice, 
# this list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the 
# documentation and/or other materials provided with the distribution.
# 
# * Neither the name of Adobe Systems Incorporated nor the names of its 
# contributors may be used to endorse or promote products derived from 
# this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR 
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

'''See readme or run with no args for usage'''

import os
import sys
import tempfile
import shutil
import struct
import zlib
import hashlib
import inspect

supportsLZMA = False
try:
	import pylzma
	supportsLZMA = True
except:
	pass

####################################
# Helpers
####################################

class stringFile(object):
	def __init__(self, data):
		self.data = data

	def read(self, num=-1):
		result = self.data[:num]
		self.data = self.data[num:]
		return result

	def close(self):
		self.data = None

	def flush(self):
		pass

def consumeSwfTag(f):
	tagBytes = b""

	recordHeaderRaw = f.read(2)
	tagBytes += recordHeaderRaw
	
	if recordHeaderRaw == "":
		raise Exception("Bad SWF: Unexpected end of file")
	recordHeader = struct.unpack("BB", recordHeaderRaw)
	tagCode = ((recordHeader[1] & 0xff) << 8) | (recordHeader[0] & 0xff)
	tagType = (tagCode >> 6)
	tagLength = tagCode & 0x3f
	if tagLength == 0x3f:
		ll = f.read(4)
		longlength = struct.unpack("BBBB", ll)
		tagLength = ((longlength[3]&0xff) << 24) | ((longlength[2]&0xff) << 16) | ((longlength[1]&0xff) << 8) | (longlength[0]&0xff)
		tagBytes += ll
	tagBytes += f.read(tagLength)
	return (tagType, tagBytes)

def outputInt(o, i):
	o.write(struct.pack('I', i))

def outputTelemetryTag(o, passwordClear):

	lengthBytes = 2 # reserve
	if passwordClear:
		sha = hashlib.sha256()
		sha.update(passwordClear)
		passwordDigest = sha.digest()
		lengthBytes += len(passwordDigest)

	# Record header
	code = 93
	if lengthBytes >= 63:
		o.write(struct.pack('<HI', code << 6 | 0x3f, lengthBytes))
	else:
		o.write(struct.pack('<H', code << 6 | lengthBytes))

	# Reserve
	o.write(struct.pack('<H', 0))
	
	# Password
	if passwordClear:
		o.write(passwordDigest)

####################################
# main()
####################################

if __name__ == "__main__":

	####################################
	# Parse command line
	####################################

	if len(sys.argv) < 2:
		print("Usage: %s SWF_FILE [PASSWORD]" % os.path.basename(inspect.getfile(inspect.currentframe())))
		print("\nIf PASSWORD is provided, then a password will be required to view advanced telemetry in Adobe 'Monocle'.")
		sys.exit(-1)

	infile = sys.argv[1]
	passwordClear = sys.argv[2] if len(sys.argv) >= 3 else None

	####################################
	# Process SWF header
	####################################

	swfFH = open(infile, 'rb')
	signature = swfFH.read(3)
	swfVersion = swfFH.read(1)
	struct.unpack("<I", swfFH.read(4))[0] # uncompressed length of file

	if signature == b"FWS":
		pass
	elif signature == b"CWS":
		decompressedFH = stringFile(zlib.decompressobj().decompress(swfFH.read()))
		swfFH.close()
		swfFH = decompressedFH
	elif signature == b"ZWS":
		if not supportsLZMA:
			raise Exception("You need the PyLZMA package to use this script on \
				LZMA-compressed SWFs. http://www.joachim-bauch.de/projects/pylzma/")
		swfFH.read(4) # compressed length
		decompressedFH = stringFile(pylzma.decompress(swfFH.read()))
		swfFH.close()
		swfFH = decompressedFH
	else:
		raise Exception("Bad SWF: Unrecognized signature: %s" % signature)

	f = swfFH
	o = tempfile.TemporaryFile()
	
	o.write(signature)
	o.write(swfVersion)
	outputInt(o,  0) # FileLength - we'll fix this up later

	# FrameSize - this is nasty to read because its size can vary
	rs = f.read(1)
	r = struct.unpack("B", rs)
	rbits = (r[0] & 0xff) >> 3
	rrbytes = (7 + (rbits*4) - 3) / 8;
	o.write(rs)
	o.write(f.read((int)(rrbytes)))

	o.write(f.read(4)) # FrameRate and FrameCount

	####################################
	# Process each SWF tag
	####################################

	while True:
		(tagType, tagBytes) = consumeSwfTag(f)
		if tagType == 93:
			sys.exit(0)
		elif tagType == 92:
			raise Exception("Bad SWF: Signed SWFs are not supported")
		elif tagType == 69:
			# FileAttributes tag
			o.write(tagBytes)
			
			# Look ahead for Metadata tag. If present, put our tag after it
			(nextTagType, nextTagBytes) = consumeSwfTag(f)
			writeAfterNextTag = nextTagType == 77
			if writeAfterNextTag:
				o.write(nextTagBytes)
				
			outputTelemetryTag(o, passwordClear)
			
			# If there was no Metadata tag, we still need to write that tag out
			if not writeAfterNextTag:
				o.write(nextTagBytes)
				
			(tagType, tagBytes) = consumeSwfTag(f)

		o.write(tagBytes)
		
		if tagType == 0:
			break
	
	####################################
	# Finish up
	####################################
	
	# Fix the FileLength header
	uncompressedLength = o.tell()
	o.seek(4)
	o.write(struct.pack("I", uncompressedLength))   
	o.flush()
	o.seek(0)
	
	# Copy the temp file to the outFile, compressing if necessary
	outFile = open(infile, "wb")
	if signature == b"FWS":	
		shutil.copyfileobj(o, outFile)
	else:
		outFile.write(o.read(8)) # File is compressed after header
		if signature == b"CWS":
			outFile.write(zlib.compress(o.read()))
		elif signature == b"ZWS":
			compressed = pylzma.compress(o.read())
			outputInt(outFile, len(compressed)-5) # LZMA SWF has CompressedLength header field
			outFile.write(compressed)
		else:
			assert(false)
	
	outFile.close()
	
	if passwordClear:
		print("Added Telemetry flag with encrypted password " + passwordClear + " in " + infile)
	else:
		print("Added Telemetry flag in " + infile)
