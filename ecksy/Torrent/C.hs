{-# LANGUAGE ForeignFunctionInterface, EmptyDataDecls #-}
module Torrent.C ( Sha1Hash
                 , IPFilter
                 , Torrent
                 , TorrentState(..)
                 , Session
                 , LTor( makeIPFilter
                       , addFilteredRange

                       , torrentSavePath
                       , torrentName
                       , setRatio
                       , setTorrentUploadLimit
                       , torrentUploadLimit
                       , setTorrentDownloadLimit
                       , torrentDownloadLimit
                       , pauseTorrent
                       , resumeTorrent
                       , isPaused
                       , isSeed
                       , infoHash
                       , torrentProgress
                       , torrentDownloadRate
                       , torrentUploadRate
                       , torrentState

                       , makeSession
                       , addMagnetURI
                       , pauseSession
                       , resumeSession
                       , isSessionPaused
                       , removeTorrent
                       , findTorrent
                       , getTorrents
                       , setSessionUploadRateLimit
                       , sessionUploadRateLimit
                       , setSessionDownloadRateLimit
                       , sessionDownloadRateLimit
                       , setIPFilter
                       )
                 , withLibTorrent
                 ) where

import Control.Applicative
import Control.Exception
import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.Trans.Error

import Prelude
import System.Posix.DynamicLinker

import Foreign.C.String
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array
import Foreign.Ptr

data LTor = LTor { makeIPFilter :: IO IPFilter
                 , addFilteredRange :: IPFilter -> String -> String -> IO ()

                 , torrentSavePath :: Torrent -> IO String
                 , torrentName :: Torrent -> IO String
                 , setRatio :: Torrent -> Double -> IO ()
                 , setTorrentUploadLimit :: Torrent -> Int -> IO ()
                 , torrentUploadLimit :: Torrent -> IO Int
                 , setTorrentDownloadLimit :: Torrent -> Int -> IO ()
                 , torrentDownloadLimit :: Torrent -> IO Int
                 , pauseTorrent :: Torrent -> IO ()
                 , resumeTorrent :: Torrent -> IO ()
                 , isPaused :: Torrent -> IO Bool
                 , isSeed :: Torrent -> IO Bool
                 , infoHash :: Torrent -> IO Sha1Hash
                 , torrentProgress :: Torrent -> IO Double
                 , torrentDownloadRate :: Torrent -> IO Int
                 , torrentUploadRate :: Torrent -> IO Int
                 , torrentState :: Torrent -> IO TorrentState

                 , makeSession :: IO Session
                 , addMagnetURI :: Session -> String -> String -> IO Torrent
                 , pauseSession :: Session -> IO ()
                 , resumeSession :: Session -> IO ()
                 , isSessionPaused :: Session -> IO Bool
                 , removeTorrent :: Session -> Torrent -> Bool -> IO ()
                 , findTorrent :: Session -> Sha1Hash -> IO (Maybe Torrent)
                 , getTorrents :: Session -> IO [Torrent]
                 , setSessionUploadRateLimit :: Session -> Int -> IO ()
                 , sessionUploadRateLimit :: Session -> IO Int
                 , setSessionDownloadRateLimit :: Session -> Int -> IO ()
                 , sessionDownloadRateLimit :: Session -> IO Int
                 , setIPFilter :: Session -> IPFilter -> IO ()
                 }

data TorrentState = QueuedForChecking
                  | Checking
                  | DownloadingMetadata
                  | Downloading
                  | Finished
                  | Seeding
                  | Allocating
                  | CheckingResumeData
    deriving (Show, Enum, Bounded)

data Sha1Hash_
newtype Sha1Hash = SH1 (ForeignPtr Sha1Hash_)

data IPFilter_
newtype IPFilter = IPF (ForeignPtr IPFilter_)

data Torrent_
newtype Torrent = TOR (ForeignPtr Torrent_)

data Session_
newtype Session = SES (ForeignPtr Session_)

type Err = String

validateFPtr :: String -> FunPtr a -> ErrorT Err IO (FunPtr a)
validateFPtr m f | f == nullFunPtr = throwError $ m ++ " should not be null!"
                 | otherwise      = return f

nullCheck :: Ptr a -> Ptr a
nullCheck p = assert (p /= nullPtr) p

getFunc :: DL -> String -> ErrorT Err IO (FunPtr a)
getFunc dl name = liftIO (dlsym dl name) >>= validateFPtr name

getFreeFunc :: DL -> String -> ErrorT Err IO (FunPtr (Ptr a -> IO ()))
getFreeFunc = getFunc

type MakeIPFilter = IO (Ptr IPFilter_)
foreign import ccall "dynamic"
    mkMakeIPFilter :: FunPtr MakeIPFilter -> MakeIPFilter

adaptMakeIPFilter :: FunPtr (Ptr IPFilter_ -> IO ()) -> MakeIPFilter -> IO IPFilter
adaptMakeIPFilter freeFunc f = IPF <$> (newForeignPtr freeFunc =<< nullCheck <$> f)

type AddFilteredRange = Ptr IPFilter_ -> CString -> CString -> IO ()
foreign import ccall "dynamic"
    mkAddFilteredRange :: FunPtr AddFilteredRange -> AddFilteredRange

adaptAddFilteredRange :: AddFilteredRange -> (IPFilter -> String -> String -> IO ())
adaptAddFilteredRange f (IPF fp) start' end' = withCString start' $ \start ->
                                               withCString end'   $ \end ->
                                               withForeignPtr fp  $ \p ->
                                                   f p start end

type TorrentSavePath = Ptr Torrent_ -> IO CString
foreign import ccall "dynamic"
    mkTorrentSavePath :: FunPtr TorrentSavePath -> TorrentSavePath

adaptTorrentSavePath :: TorrentSavePath -> (Torrent -> IO String)
adaptTorrentSavePath f (TOR fp) = withForeignPtr fp $ \p -> do
                                  cstr <- nullCheck <$> f p
                                  str <- peekCString =<< f p
                                  free cstr
                                  return str

type TorrentName = TorrentSavePath

mkTorrentName :: FunPtr TorrentName -> TorrentName
mkTorrentName = mkTorrentSavePath

adaptTorrentName :: TorrentName -> (Torrent -> IO String)
adaptTorrentName = adaptTorrentSavePath

type SetRatio = Ptr Torrent_ -> CFloat -> IO ()
foreign import ccall "dynamic"
    mkSetRatio :: FunPtr SetRatio -> SetRatio

adaptSetRatio :: SetRatio -> (Torrent -> Double -> IO ())
adaptSetRatio f (TOR fp) r = withForeignPtr fp $ \p ->
                             f p $ realToFrac r

type SetTorrentLimit = Ptr Torrent_ -> CInt -> IO ()
foreign import ccall "dynamic"
    mkSetTorrentLimit :: FunPtr SetTorrentLimit -> SetTorrentLimit

adaptSetTorrentLimit :: SetTorrentLimit -> (Torrent -> Int -> IO ())
adaptSetTorrentLimit f (TOR fp) lim = withForeignPtr fp $ \p ->
                                      f p $ fromIntegral lim

type GetTorrentLimit = Ptr Torrent_ -> IO CInt
foreign import ccall "dynamic"
    mkGetTorrentLimit :: FunPtr GetTorrentLimit -> GetTorrentLimit

adaptGetTorrentLimit :: GetTorrentLimit -> (Torrent -> IO Int)
adaptGetTorrentLimit f (TOR fp) = withForeignPtr fp $ \p ->
                                  fromIntegral <$> f p

type TorrentAction = Ptr Torrent_ -> IO ()
foreign import ccall "dynamic"
    mkTorrentAction :: FunPtr TorrentAction -> TorrentAction

adaptTorrentAction :: TorrentAction -> (Torrent -> IO ())
adaptTorrentAction f (TOR fp) = withForeignPtr fp f

type TorrentBool = Ptr Torrent_ -> IO CInt
foreign import ccall "dynamic"
    mkTorrentBool :: FunPtr TorrentBool -> TorrentBool

adaptTorrentBool :: TorrentBool -> (Torrent -> IO Bool)
adaptTorrentBool f (TOR fp) = withForeignPtr fp $ \p -> do
                              r <- f p
                              case r of
                                0 -> return False
                                _ -> return True

type InfoHash = Ptr Torrent_ -> IO (Ptr Sha1Hash_)
foreign import ccall "dynamic"
    mkInfoHash :: FunPtr InfoHash -> InfoHash

adaptInfoHash :: FunPtr (Ptr Sha1Hash_ -> IO ()) -> InfoHash -> (Torrent -> IO Sha1Hash)
adaptInfoHash freeFunc f (TOR fp) = withForeignPtr fp $ \p -> do
                                    h <- nullCheck <$> f p
                                    SH1 <$> newForeignPtr freeFunc h

type TorrentProgress = Ptr Torrent_ -> IO CFloat
foreign import ccall "dynamic"
    mkTorrentProgress :: FunPtr TorrentProgress -> TorrentProgress

adaptTorrentProgress :: TorrentProgress -> (Torrent -> IO Double)
adaptTorrentProgress f (TOR fp) = withForeignPtr fp $ \p ->
                                  realToFrac <$> f p

-- Limits and rates have the same data types.
mkGetTorrentRate :: FunPtr GetTorrentLimit -> GetTorrentLimit
mkGetTorrentRate = mkGetTorrentLimit
adaptGetTorrentRate :: GetTorrentLimit -> Torrent -> IO Int
adaptGetTorrentRate = adaptGetTorrentLimit

type TorrentStateFunc = Ptr Torrent_ ->  IO CInt
foreign import ccall "dynamic"
    mkTorrentState :: FunPtr TorrentStateFunc -> TorrentStateFunc

adaptTorrentState :: TorrentStateFunc -> (Torrent -> IO TorrentState)
adaptTorrentState f (TOR fp) = withForeignPtr fp $ \p ->
                               toEnum <$> fromIntegral <$> f p

type MakeSession = IO (Ptr Session_)
foreign import ccall "dynamic"
    mkMakeSession :: FunPtr MakeSession -> MakeSession

adaptMakeSession :: FunPtr (Ptr Session_ -> IO ()) -> MakeSession -> IO Session
adaptMakeSession freeFunc f = SES <$> (newForeignPtr freeFunc =<< nullCheck <$> f)

type AddMagnetURI = Ptr Session_ -> CString -> CString -> IO (Ptr Torrent_)
foreign import ccall "dynamic"
    mkAddMagnetURI :: FunPtr AddMagnetURI -> AddMagnetURI

adaptAddMagnetURI :: FunPtr (Ptr Torrent_ -> IO ()) -> AddMagnetURI -> (Session -> String -> String -> IO Torrent)
adaptAddMagnetURI freeFunc f (SES s') uri' tgt' = withForeignPtr s' $ \s ->
                                                  withCString uri' $ \uri ->
                                                  withCString tgt' $ \tgt ->
                                                  TOR <$> (newForeignPtr freeFunc =<< nullCheck <$> f s uri tgt)

type SessionAction = Ptr Session_ -> IO ()
foreign import ccall "dynamic"
    mkSessionAction :: FunPtr SessionAction -> SessionAction

adaptSessionAction :: SessionAction -> (Session -> IO ())
adaptSessionAction f (SES s) = withForeignPtr s f

type SessionPaused = Ptr Session_ -> IO CInt
foreign import ccall "dynamic"
    mkSessionPaused :: FunPtr SessionPaused -> SessionPaused

adaptSessionPaused :: SessionPaused -> (Session -> IO Bool)
adaptSessionPaused f (SES s) = withForeignPtr s $ \p -> do
                               r <- f p
                               case r of
                                  0 -> return False
                                  _ -> return True

type RemoveTorrent = Ptr Session_ -> Ptr Torrent_ -> CInt -> IO ()
foreign import ccall "dynamic"
    mkRemoveTorrent :: FunPtr RemoveTorrent -> RemoveTorrent

adaptRemoveTorrent :: RemoveTorrent -> (Session -> Torrent -> Bool -> IO ())
adaptRemoveTorrent f (SES s') (TOR t') del = withForeignPtr s' $ \s ->
                                             withForeignPtr t' $ \t ->
                                             f s t . fromIntegral $ fromEnum del

type FindTorrent = Ptr Session_ -> Ptr Sha1Hash_ -> IO (Ptr Torrent_)
foreign import ccall "dynamic"
    mkFindTorrent :: FunPtr FindTorrent -> FindTorrent

adaptFindTorrent :: FunPtr (Ptr Torrent_ -> IO ()) -> FindTorrent -> (Session -> Sha1Hash -> IO (Maybe Torrent))
adaptFindTorrent freeFunc f (SES s') (SH1 h') = withForeignPtr s' $ \s ->
                                                withForeignPtr h' $ \h ->
                                                getRet =<< f s h
    where
        getRet p | p == nullPtr = return Nothing
                 | otherwise   = Just . TOR <$> newForeignPtr freeFunc p

data TorrentList_
type TorrentList  = ForeignPtr TorrentList_

type TListElems = Ptr TorrentList_ -> IO CInt
foreign import ccall "dynamic"
    mkTListElems :: FunPtr TListElems -> TListElems

adaptTListElems :: TListElems -> (TorrentList -> IO Int)
adaptTListElems f fp = withForeignPtr fp $ (fromIntegral <$>) . f

type TListDump = Ptr TorrentList_ -> Ptr (Ptr Torrent_) -> IO ()
foreign import ccall "dynamic"
    mkTListDump :: FunPtr TListDump -> TListDump

adaptTListDump :: FunPtr (Ptr Torrent_ -> IO ())
               -> (TorrentList -> IO Int)
               -> TListDump
               -> (TorrentList -> IO [Torrent])
adaptTListDump fTor getLen f fp = do len <- getLen fp
                                     (mapM ((TOR <$>) . newForeignPtr fTor) =<<) $
                                       withForeignPtr fp $ \p ->
                                        allocaArray len $ \tors ->
                                         f p tors >> peekArray len tors

type GetTorrents = Ptr Session_ -> IO (Ptr TorrentList_)
foreign import ccall "dynamic"
    mkGetTorrents :: FunPtr GetTorrents -> GetTorrents

adaptGetTorrents :: DL
                 -> GetTorrents
                 -> ErrorT Err IO (Session -> IO [Torrent])
adaptGetTorrents dl f = do f_tl <- getFreeFunc dl "free_torrent_list"
                           f_th <- getFreeFunc dl "free_torrent_handle"
                           tl_elems <- adaptTListElems <$> mkTListElems <$> getFunc dl "tlist_elems"
                           tl_dump <- adaptTListDump f_th tl_elems <$> mkTListDump <$> getFunc dl "tlist_dump"

                           return $ \(SES s) -> withForeignPtr s $ \p ->
                                                tl_dump =<< newForeignPtr f_tl =<< f p

type SetSessionLimit = Ptr Session_ -> CInt -> IO ()
foreign import ccall "dynamic"
    mkSetSessionLimit :: FunPtr SetSessionLimit -> SetSessionLimit

adaptSetSessionLimit :: SetSessionLimit -> (Session -> Int -> IO ())
adaptSetSessionLimit f (SES s) lim = withForeignPtr s $ \p ->
                                     f p $ fromIntegral lim

type GetSessionLimit = Ptr Session_ -> IO CInt
foreign import ccall "dynamic"
    mkGetSessionLimit :: FunPtr GetSessionLimit -> GetSessionLimit

adaptGetSessionLimit :: GetSessionLimit -> (Session -> IO Int)
adaptGetSessionLimit f (SES s) = withForeignPtr s $ \p ->
                                 fromIntegral <$> f p

type SetIPFilter = Ptr Session_ -> Ptr IPFilter_ -> IO ()
foreign import ccall "dynamic"
    mkSetIPFilter :: FunPtr SetIPFilter -> SetIPFilter

adaptSetIPFilter :: SetIPFilter -> (Session -> IPFilter -> IO ())
adaptSetIPFilter f (SES s') (IPF filt) = withForeignPtr s' $ \s ->
                                         withForeignPtr filt $ f s

-- | Dynamically loads the libtorrent C bindings. If an error occurs, it will
--   be in Left. Otherwise, the passed function will be executed with a valid
--   LibTorrent instance.
withLibTorrent :: (LTor -> IO a) -> IO (Either String a)
withLibTorrent f = withDL "liblibtorrent-c.so" [ RTLD_LAZY ] $ \dl -> runErrorT $ do
                    f_s1h   <- getFreeFunc dl "free_sha1_hash"
                    f_ipf   <- getFreeFunc dl "free_ip_filter"
                    f_th    <- getFreeFunc dl "free_torrent_handle"
                    f_ses   <- getFreeFunc dl "free_session"

                    liftIO . f =<< LTor <$> (adaptMakeIPFilter f_ipf <$> mkMakeIPFilter     <$> getFunc dl "make_ip_filter")
                                        <*> (adaptAddFilteredRange   <$> mkAddFilteredRange <$> getFunc dl "add_filtered_range")

                                        <*> (adaptTorrentSavePath    <$> mkTorrentSavePath  <$> getFunc dl "torrent_save_path")
                                        <*> (adaptTorrentName        <$> mkTorrentName      <$> getFunc dl "torrent_name")
                                        <*> (adaptSetRatio           <$> mkSetRatio         <$> getFunc dl "set_ratio")
                                        <*> (adaptSetTorrentLimit    <$> mkSetTorrentLimit  <$> getFunc dl "set_torrent_upload_limit")
                                        <*> (adaptGetTorrentLimit    <$> mkGetTorrentLimit  <$> getFunc dl "get_torrent_upload_limit")
                                        <*> (adaptSetTorrentLimit    <$> mkSetTorrentLimit  <$> getFunc dl "set_torrent_download_limit")
                                        <*> (adaptGetTorrentLimit    <$> mkGetTorrentLimit  <$> getFunc dl "get_torrent_download_limit")
                                        <*> (adaptTorrentAction      <$> mkTorrentAction    <$> getFunc dl "pause_torrent")
                                        <*> (adaptTorrentAction      <$> mkTorrentAction    <$> getFunc dl "resume_torrent")
                                        <*> (adaptTorrentBool        <$> mkTorrentBool      <$> getFunc dl "is_paused")
                                        <*> (adaptTorrentBool        <$> mkTorrentBool      <$> getFunc dl "is_seed")
                                        <*> (adaptInfoHash f_s1h     <$> mkInfoHash         <$> getFunc dl "info_hash")
                                        <*> (adaptTorrentProgress    <$> mkTorrentProgress  <$> getFunc dl "torrent_progress")
                                        <*> (adaptGetTorrentRate     <$> mkGetTorrentRate   <$> getFunc dl "torrent_download_rate")
                                        <*> (adaptGetTorrentRate     <$> mkGetTorrentRate   <$> getFunc dl "torrent_upload_rate")
                                        <*> (adaptTorrentState       <$> mkTorrentState     <$> getFunc dl "torrent_state")

                                        <*> (adaptMakeSession f_ses  <$> mkMakeSession      <$> getFunc dl "make_session")
                                        <*> (adaptAddMagnetURI f_th  <$> mkAddMagnetURI     <$> getFunc dl "add_magnet_uri")
                                        <*> (adaptSessionAction      <$> mkSessionAction    <$> getFunc dl "pause_session")
                                        <*> (adaptSessionAction      <$> mkSessionAction    <$> getFunc dl "resume_session")
                                        <*> (adaptSessionPaused      <$> mkSessionPaused    <$> getFunc dl "is_session_paused")
                                        <*> (adaptRemoveTorrent      <$> mkRemoveTorrent    <$> getFunc dl "remove_torrent")
                                        <*> (adaptFindTorrent f_th   <$> mkFindTorrent      <$> getFunc dl "find_torrent")
                                        <*> (adaptGetTorrents dl     =<< mkGetTorrents      <$> getFunc dl "get_torrents")
                                        <*> (adaptSetSessionLimit    <$> mkSetSessionLimit  <$> getFunc dl "set_session_upload_rate_limit")
                                        <*> (adaptGetSessionLimit    <$> mkGetSessionLimit  <$> getFunc dl "session_upload_rate_limit")
                                        <*> (adaptSetSessionLimit    <$> mkSetSessionLimit  <$> getFunc dl "set_session_download_rate_limit")
                                        <*> (adaptGetSessionLimit    <$> mkGetSessionLimit  <$> getFunc dl "session_download_rate_limit")
                                        <*> (adaptSetIPFilter        <$> mkSetIPFilter      <$> getFunc dl "set_ip_filter")
