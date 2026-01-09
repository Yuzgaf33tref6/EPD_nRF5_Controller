// EPD command constants mirroring the original web app
class EpdCmd {
  static const int SET_PINS = 0x00;
  static const int INIT = 0x01;
  static const int CLEAR = 0x02;
  static const int SEND_CMD = 0x03;
  static const int SEND_DATA = 0x04;
  static const int REFRESH = 0x05;
  static const int SLEEP = 0x06;
  static const int SET_TIME = 0x20;
  static const int WRITE_IMG = 0x30;
}
