{-# LANGUAGE ScopedTypeVariables, PatternGuards #-}

-- | Reading and writing uncompressed 24 bit BMP files.
--	We only handle Windows V3 file headers, but this is the most common.
--
-- To write a file do something like:
--
--  > do let bmp    =  packRGBA32ToBMP width height $ Data.ByteString.pack [some list of Word8s]
--  >    handle     <- openFile fileName WriteMode
--  >    hPutBMP handle bmp
--
-- To read a file do something like:
--
--  > do handle     <- openFile fileName ReadMode
--  >    Right bmp  <- hGetBMP handle 
--  >    let rgba   =  unpackBMPToRGBA32 bmp
--  >    let (width, height) = bmpDimensions bmp
--  >    ... 
--  
module Codec.BMP
	( BMP		(..)
	, FileHeader	(..)
	, BitmapInfo    (..)
	, BitmapInfoV3	(..)
	, Error         (..)
	, hGetBMP
	, hPutBMP
	, unpackBMPToRGBA32
	, packRGBA32ToBMP 
	, bmpDimensions)
where
import Codec.BMP.Base
import Codec.BMP.Error
import Codec.BMP.Unpack
import Codec.BMP.Pack
import Codec.BMP.FileHeader
import Codec.BMP.BitmapInfo
import Data.Binary
import Data.Maybe
import System.IO
import Data.ByteString		as BS
import Data.ByteString.Lazy	as BSL

		
-- | Get a BMP image from a file handle.
--	The file is checked for problems and unsupported features when read.
--	If there is anything wrong this gives an `Error` instead.
hGetBMP :: Handle -> IO (Either Error BMP)
hGetBMP h
 = do	-- load the file header.
	buf	<- BSL.hGet h sizeOfFileHeader
	if (fromIntegral $ BSL.length buf) /= sizeOfFileHeader
	 then 	return $ Left ErrorReadOfFileHeaderFailed
	 else	hGetBMP2 h (decode buf)
	
	
hGetBMP2 h fileHeader
 -- Check the magic before doing anything else.
 --	If the specified file is not a BMP file then we'd prefer to get 
 --	this error than a `ReadOfImageHeaderFailed`.
 | fileHeaderType fileHeader /= bmpMagic
 = return $ Left $ ErrorBadMagic (fileHeaderType fileHeader)
	
 | otherwise
 = do	-- load the image header.
	buf	<- BSL.hGet h sizeOfBitmapInfoV3
	if (fromIntegral $ BSL.length buf) /= sizeOfBitmapInfoV3
	 then 	return $ Left ErrorReadOfImageHeaderFailed
	 else 	hGetBMP3 h fileHeader (decode buf)
			
hGetBMP3 h fileHeader imageHeader
 | (err : _)	<- catMaybes
			[ checkFileHeader   fileHeader
			, checkBitmapInfoV3 imageHeader]
 = return $ Left err

 | otherwise
 = do	-- load the image data.
	let len		= fromIntegral $ dib3ImageSize imageHeader
	imageData	<- BS.hGet h len
				
	if (fromIntegral $ BS.length imageData) /= len
	 then return $ Left ErrorReadOfImageDataFailed
	 else return 
		$ Right $ BMP 
		{ bmpFileHeader 	= fileHeader
		, bmpBitmapInfo		= InfoV3 imageHeader
		, bmpRawImageData	= imageData }


-- | Write a BMP image to a file handle.
--	The size of the provided image data is checked against the given dimensions.
--	If these don't match then an error is thrown.
hPutBMP :: Handle -> BMP -> IO ()
hPutBMP h bmp
 = do	BSL.hPut h (encode $ bmpFileHeader bmp)
	BSL.hPut h (encode $ bmpBitmapInfo bmp)
	BS.hPut h $ bmpRawImageData bmp


-- | Get the width and height of an image.
--	It's better to use this function than to access the headers directly.
bmpDimensions :: BMP -> (Int, Int)
bmpDimensions bmp
 = case bmpBitmapInfo bmp of
	InfoV3 info
	 -> ( fromIntegral $ dib3Width info
	    , fromIntegral $ dib3Height info)

