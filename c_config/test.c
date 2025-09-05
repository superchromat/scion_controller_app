#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>


uint32_t tosc_writeMessage(char *,int ,char *,char *, ... ) { return (0); }
#define OSC_BUF_SIZE 128



typedef struct ConfigAnalogFormat {
  const char* resolution;
  double framerate;
  const char* colourspace;
  double color_matrix[3][3];
} ConfigAnalogFormat;

typedef struct ConfigSendLut {
  double Y[32];
  double R[32];
  double G[32];
  double B[32];
} ConfigSendLut;

typedef struct ConfigSend {
  int source;
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
  ConfigSendLut lut;
} ConfigSend;

typedef struct Config {
  ConfigAnalogFormat analog_format;
  double clock_offset;
  ConfigSend send[4];
} Config;

Config config =
{
  .analog_format = {
    .resolution = "1920x1080",
    .framerate = 60.0,
    .colourspace = "RGB",
    .color_matrix = {
      { 1.0, 0.0, 0.0 },
      { 0.0, 1.0, 0.0 },
      { 0.0, 0.0, 1.0 }
    }
  },
  .clock_offset = 0.0,
  .send = {
    {
      .source = 1,
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
      .hue = 0.0,
      .lut = {
        .Y = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .R = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .G = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .B = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 }
      }
    },
    {
      .source = 2,
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
      .hue = 0.0,
      .lut = {
        .Y = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .R = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .G = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .B = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 }
      }
    },
    {
      .source = 3,
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
      .hue = 0.0,
      .lut = {
        .Y = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .R = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .G = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .B = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 }
      }
    },
    {
      .source = 4,
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
      .hue = 0.0,
      .lut = {
        .Y = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .R = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .G = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 },
        .B = { -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, 0.0, 0.0, 1.0, 1.0 }
      }
    }
  }
};

// Generated OSC getters/setters
/*
** analog_format_resolution
*/
uint32_t get_analog_format_resolution(char *buf, int len) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/analog_format/resolution");
  return tosc_writeMessage(buf, len, address, "s", config.analog_format.resolution);
}
void set_analog_format_resolution(const char *s) { config.analog_format.resolution = s; }
/*
** analog_format_framerate
*/
uint32_t get_analog_format_framerate(char *buf, int len) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/analog_format/framerate");
  return tosc_writeMessage(buf, len, address, "f", config.analog_format.framerate);
}
void set_analog_format_framerate(double v) { config.analog_format.framerate = v; }
/*
** analog_format_colourspace
*/
uint32_t get_analog_format_colourspace(char *buf, int len) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/analog_format/colourspace");
  return tosc_writeMessage(buf, len, address, "s", config.analog_format.colourspace);
}
void set_analog_format_colourspace(const char *s) { config.analog_format.colourspace = s; }
/*
** analog_format_color_matrix
*/
uint32_t get_analog_format_color_matrix(char *buf, int len) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/analog_format/color_matrix");
  return tosc_writeMessage(buf, len, address, "fffffffff",
    config.analog_format.color_matrix[0][0],
    config.analog_format.color_matrix[0][1],
    config.analog_format.color_matrix[0][2],
    config.analog_format.color_matrix[1][0],
    config.analog_format.color_matrix[1][1],
    config.analog_format.color_matrix[1][2],
    config.analog_format.color_matrix[2][0],
    config.analog_format.color_matrix[2][1],
    config.analog_format.color_matrix[2][2]);
}
void set_analog_format_color_matrix(int row, int col, double v) { config.analog_format.color_matrix[row][col] = v; }
/*
** clock_offset
*/
uint32_t get_clock_offset(char *buf, int len) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/clock_offset");
  return tosc_writeMessage(buf, len, address, "f", config.clock_offset);
}
void set_clock_offset(double v) { config.clock_offset = v; }
/*
** send_source
*/
uint32_t get_send_source(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/source",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].source);
}
void set_send_source(int send_idx, double v) { config.send[send_idx].source = v; }
/*
** send_scaleX
*/
uint32_t get_send_scaleX(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/scaleX",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].scaleX);
}
void set_send_scaleX(int send_idx, double v) { config.send[send_idx].scaleX = v; }
/*
** send_scaleY
*/
uint32_t get_send_scaleY(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/scaleY",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].scaleY);
}
void set_send_scaleY(int send_idx, double v) { config.send[send_idx].scaleY = v; }
/*
** send_posX
*/
uint32_t get_send_posX(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/posX",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].posX);
}
void set_send_posX(int send_idx, double v) { config.send[send_idx].posX = v; }
/*
** send_posY
*/
uint32_t get_send_posY(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/posY",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].posY);
}
void set_send_posY(int send_idx, double v) { config.send[send_idx].posY = v; }
/*
** send_rotation
*/
uint32_t get_send_rotation(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/rotation",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].rotation);
}
void set_send_rotation(int send_idx, double v) { config.send[send_idx].rotation = v; }
/*
** send_pitch
*/
uint32_t get_send_pitch(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/pitch",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].pitch);
}
void set_send_pitch(int send_idx, double v) { config.send[send_idx].pitch = v; }
/*
** send_yaw
*/
uint32_t get_send_yaw(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/yaw",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].yaw);
}
void set_send_yaw(int send_idx, double v) { config.send[send_idx].yaw = v; }
/*
** send_brightness
*/
uint32_t get_send_brightness(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/brightness",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].brightness);
}
void set_send_brightness(int send_idx, double v) { config.send[send_idx].brightness = v; }
/*
** send_contrast
*/
uint32_t get_send_contrast(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/contrast",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].contrast);
}
void set_send_contrast(int send_idx, double v) { config.send[send_idx].contrast = v; }
/*
** send_saturation
*/
uint32_t get_send_saturation(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/saturation",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].saturation);
}
void set_send_saturation(int send_idx, double v) { config.send[send_idx].saturation = v; }
/*
** send_hue
*/
uint32_t get_send_hue(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/hue",send_idx);
  return tosc_writeMessage(buf, len, address, "f", config.send[send_idx].hue);
}
void set_send_hue(int send_idx, double v) { config.send[send_idx].hue = v; }
/*
** send_lut_Y
*/
uint32_t get_send_lut_Y(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/lut/Y", send_idx);
  return tosc_writeMessage(buf, len, address, "ffffffffffffffffffffffffffffffff",
    config.send[send_idx].lut.Y[0],
    config.send[send_idx].lut.Y[1],
    config.send[send_idx].lut.Y[2],
    config.send[send_idx].lut.Y[3],
    config.send[send_idx].lut.Y[4],
    config.send[send_idx].lut.Y[5],
    config.send[send_idx].lut.Y[6],
    config.send[send_idx].lut.Y[7],
    config.send[send_idx].lut.Y[8],
    config.send[send_idx].lut.Y[9],
    config.send[send_idx].lut.Y[10],
    config.send[send_idx].lut.Y[11],
    config.send[send_idx].lut.Y[12],
    config.send[send_idx].lut.Y[13],
    config.send[send_idx].lut.Y[14],
    config.send[send_idx].lut.Y[15],
    config.send[send_idx].lut.Y[16],
    config.send[send_idx].lut.Y[17],
    config.send[send_idx].lut.Y[18],
    config.send[send_idx].lut.Y[19],
    config.send[send_idx].lut.Y[20],
    config.send[send_idx].lut.Y[21],
    config.send[send_idx].lut.Y[22],
    config.send[send_idx].lut.Y[23],
    config.send[send_idx].lut.Y[24],
    config.send[send_idx].lut.Y[25],
    config.send[send_idx].lut.Y[26],
    config.send[send_idx].lut.Y[27],
    config.send[send_idx].lut.Y[28],
    config.send[send_idx].lut.Y[29],
    config.send[send_idx].lut.Y[30],
    config.send[send_idx].lut.Y[31]
  );
}
void set_send_lut_Y(int send_idx, double *v) { memcpy(config.send[send_idx].lut.Y, v, sizeof(double) * 32); }
/*
** send_lut_R
*/
uint32_t get_send_lut_R(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/lut/R", send_idx);
  return tosc_writeMessage(buf, len, address, "ffffffffffffffffffffffffffffffff",
    config.send[send_idx].lut.R[0],
    config.send[send_idx].lut.R[1],
    config.send[send_idx].lut.R[2],
    config.send[send_idx].lut.R[3],
    config.send[send_idx].lut.R[4],
    config.send[send_idx].lut.R[5],
    config.send[send_idx].lut.R[6],
    config.send[send_idx].lut.R[7],
    config.send[send_idx].lut.R[8],
    config.send[send_idx].lut.R[9],
    config.send[send_idx].lut.R[10],
    config.send[send_idx].lut.R[11],
    config.send[send_idx].lut.R[12],
    config.send[send_idx].lut.R[13],
    config.send[send_idx].lut.R[14],
    config.send[send_idx].lut.R[15],
    config.send[send_idx].lut.R[16],
    config.send[send_idx].lut.R[17],
    config.send[send_idx].lut.R[18],
    config.send[send_idx].lut.R[19],
    config.send[send_idx].lut.R[20],
    config.send[send_idx].lut.R[21],
    config.send[send_idx].lut.R[22],
    config.send[send_idx].lut.R[23],
    config.send[send_idx].lut.R[24],
    config.send[send_idx].lut.R[25],
    config.send[send_idx].lut.R[26],
    config.send[send_idx].lut.R[27],
    config.send[send_idx].lut.R[28],
    config.send[send_idx].lut.R[29],
    config.send[send_idx].lut.R[30],
    config.send[send_idx].lut.R[31]
  );
}
void set_send_lut_R(int send_idx, double *v) { memcpy(config.send[send_idx].lut.R, v, sizeof(double) * 32); }
/*
** send_lut_G
*/
uint32_t get_send_lut_G(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/lut/G", send_idx);
  return tosc_writeMessage(buf, len, address, "ffffffffffffffffffffffffffffffff",
    config.send[send_idx].lut.G[0],
    config.send[send_idx].lut.G[1],
    config.send[send_idx].lut.G[2],
    config.send[send_idx].lut.G[3],
    config.send[send_idx].lut.G[4],
    config.send[send_idx].lut.G[5],
    config.send[send_idx].lut.G[6],
    config.send[send_idx].lut.G[7],
    config.send[send_idx].lut.G[8],
    config.send[send_idx].lut.G[9],
    config.send[send_idx].lut.G[10],
    config.send[send_idx].lut.G[11],
    config.send[send_idx].lut.G[12],
    config.send[send_idx].lut.G[13],
    config.send[send_idx].lut.G[14],
    config.send[send_idx].lut.G[15],
    config.send[send_idx].lut.G[16],
    config.send[send_idx].lut.G[17],
    config.send[send_idx].lut.G[18],
    config.send[send_idx].lut.G[19],
    config.send[send_idx].lut.G[20],
    config.send[send_idx].lut.G[21],
    config.send[send_idx].lut.G[22],
    config.send[send_idx].lut.G[23],
    config.send[send_idx].lut.G[24],
    config.send[send_idx].lut.G[25],
    config.send[send_idx].lut.G[26],
    config.send[send_idx].lut.G[27],
    config.send[send_idx].lut.G[28],
    config.send[send_idx].lut.G[29],
    config.send[send_idx].lut.G[30],
    config.send[send_idx].lut.G[31]
  );
}
void set_send_lut_G(int send_idx, double *v) { memcpy(config.send[send_idx].lut.G, v, sizeof(double) * 32); }
/*
** send_lut_B
*/
uint32_t get_send_lut_B(char *buf, int len, int send_idx) {
  char address[OSC_BUF_SIZE];
  snprintf(address, OSC_BUF_SIZE-1, "/send/%d/lut/B", send_idx);
  return tosc_writeMessage(buf, len, address, "ffffffffffffffffffffffffffffffff",
    config.send[send_idx].lut.B[0],
    config.send[send_idx].lut.B[1],
    config.send[send_idx].lut.B[2],
    config.send[send_idx].lut.B[3],
    config.send[send_idx].lut.B[4],
    config.send[send_idx].lut.B[5],
    config.send[send_idx].lut.B[6],
    config.send[send_idx].lut.B[7],
    config.send[send_idx].lut.B[8],
    config.send[send_idx].lut.B[9],
    config.send[send_idx].lut.B[10],
    config.send[send_idx].lut.B[11],
    config.send[send_idx].lut.B[12],
    config.send[send_idx].lut.B[13],
    config.send[send_idx].lut.B[14],
    config.send[send_idx].lut.B[15],
    config.send[send_idx].lut.B[16],
    config.send[send_idx].lut.B[17],
    config.send[send_idx].lut.B[18],
    config.send[send_idx].lut.B[19],
    config.send[send_idx].lut.B[20],
    config.send[send_idx].lut.B[21],
    config.send[send_idx].lut.B[22],
    config.send[send_idx].lut.B[23],
    config.send[send_idx].lut.B[24],
    config.send[send_idx].lut.B[25],
    config.send[send_idx].lut.B[26],
    config.send[send_idx].lut.B[27],
    config.send[send_idx].lut.B[28],
    config.send[send_idx].lut.B[29],
    config.send[send_idx].lut.B[30],
    config.send[send_idx].lut.B[31]
  );
}
void set_send_lut_B(int send_idx, double *v) { memcpy(config.send[send_idx].lut.B, v, sizeof(double) * 32); }
// Generated sync_all routine
void sync_all(char *buf, int len) {
  // sync analog_format_resolution
  get_analog_format_resolution(buf,len);
  // sync analog_format_framerate
  get_analog_format_framerate(buf,len);
  // sync analog_format_colourspace
  get_analog_format_colourspace(buf,len);
  // sync analog_format_color_matrix matrix
  get_analog_format_color_matrix(buf, len);
  // sync clock_offset
  get_clock_offset(buf,len);
  // sync send
  for(int send_idx=0; send_idx<4; ++send_idx) { get_send(buf,len,send_idx); }
  // sync send_source
  get_send_source(buf,len,0);
  // sync send_scaleX
  get_send_scaleX(buf,len,0);
  // sync send_scaleY
  get_send_scaleY(buf,len,0);
  // sync send_posX
  get_send_posX(buf,len,0);
  // sync send_posY
  get_send_posY(buf,len,0);
  // sync send_rotation
  get_send_rotation(buf,len,0);
  // sync send_pitch
  get_send_pitch(buf,len,0);
  // sync send_yaw
  get_send_yaw(buf,len,0);
  // sync send_brightness
  get_send_brightness(buf,len,0);
  // sync send_contrast
  get_send_contrast(buf,len,0);
  // sync send_saturation
  get_send_saturation(buf,len,0);
  // sync send_hue
  get_send_hue(buf,len,0);
  // sync send_lut_Y array
  for(int send_idx=0; send_idx<4; ++send_idx) get_send_lut_Y(buf,len,send_idx);
  // sync send_lut_R array
  for(int send_idx=0; send_idx<4; ++send_idx) get_send_lut_R(buf,len,send_idx);
  // sync send_lut_G array
  for(int send_idx=0; send_idx<4; ++send_idx) get_send_lut_G(buf,len,send_idx);
  // sync send_lut_B array
  for(int send_idx=0; send_idx<4; ++send_idx) get_send_lut_B(buf,len,send_idx);
}


int main (void) { return (0); }
