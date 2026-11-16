#import <CoreAudio/CoreAudio.h>

typedef enum {
    TWMicIdle, TWMicInUse, TWMicActivityUnknown
} TWMicActivity;

TWMicActivity TWOtherMicActivity(AudioDeviceID selected);
