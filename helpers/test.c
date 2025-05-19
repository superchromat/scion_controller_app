#include <stdbool.h>
#include <stddef.h>

typedef struct ConfigAnalogFormat {
  const char* resolution;
  double framerate;
  const char* colourspace;
  double color_matrix[3][3];
} ConfigAnalogFormat;

typedef struct ConfigSend {
  int input;
  double scaleX;
  double scaleY;
  double posX;
  double posY;
  double rotation;
  double pitch;
  double yaw;
  double brightness;
  double contrast;
  double saturation;
  double hue;
} ConfigSend;

typedef struct Config {
  ConfigAnalogFormat analog_format;
  double clock_offset;
  ConfigSend send[4];
} Config;

Config config =
{
  .analog_format =
  {
    .resolution = "1920x1080",
    .framerate = 60.0,
    .colourspace = "RGB",
    .color_matrix =
    {
      { -2.0, -2.0, -2.0 },
      { 0.0, 1.0, 0.0 },
      { 0.0, 0.0, 1.0 }
    }
  },
  .clock_offset = 0.0,
  .send =
  {
    {
      .input = 1,
      .scaleX = 1.0,
      .scaleY = 1.0,
      .posX = 0.0,
      .posY = 0.0,
      .rotation = 0.0,
      .pitch = 0.0,
      .yaw = 0.0,
      .brightness = 0.5,
      .contrast = 0.5,
      .saturation = 0.5,
      .hue = 0.0
    },
    {
      .input = 2,
      .scaleX = 1.0,
      .scaleY = 1.0,
      .posX = 0.0,
      .posY = 0.0,
      .rotation = 0.0,
      .pitch = 0.0,
      .yaw = 0.0,
      .brightness = 0.5,
      .contrast = 0.5,
      .saturation = 0.5,
      .hue = 0.0
    },
    {
      .input = 3,
      .scaleX = 1.0,
      .scaleY = 1.0,
      .posX = 0.0,
      .posY = 0.0,
      .rotation = 0.0,
      .pitch = 0.0,
      .yaw = 0.0,
      .brightness = 0.5,
      .contrast = 0.5,
      .saturation = 0.5,
      .hue = 0.0
    },
    {
      .input = 4,
      .scaleX = 1.0,
      .scaleY = 1.0,
      .posX = 0.0,
      .posY = 0.0,
      .rotation = 0.0,
      .pitch = 0.0,
      .yaw = 0.0,
      .brightness = 0.5,
      .contrast = 0.5,
      .saturation = 0.5,
      .hue = 0.0
    }
  }
};
