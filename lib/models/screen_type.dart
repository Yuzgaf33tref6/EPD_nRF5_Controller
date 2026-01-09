// Placeholder for screen type definitions
class ScreenType {
  final String name;
  final int width;
  final int height;
  final String driver;

  const ScreenType(this.name, this.width, this.height, this.driver);

  static const List<ScreenType> presets = [
    ScreenType('4.2_400_300', 400, 300, 'UC8176'),
  ];
}
