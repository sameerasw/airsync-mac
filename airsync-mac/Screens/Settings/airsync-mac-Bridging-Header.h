//
//  airsync-mac-Bridging-Header.h
//  airsync-mac
//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//  You must set the 'Objective-C Bridging Header' build setting in your Xcode project.
//

#ifndef airsync_mac_Bridging_Header_h
#define airsync_mac_Bridging_Header_h

// Import the required FFmpeg libraries
#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libavutil/channel_layout.h>
#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

#endif /* airsync_mac_Bridging_Header_h */
