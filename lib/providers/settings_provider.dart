import 'package:flutter/foundation.dart';

class SettingsProvider extends ChangeNotifier {
  String _primaryLanguage = 'en';
  String _secondaryLanguage = 'ja';

  final List<String> _searchsettings = ['safe'];

  String get primaryLanguage => _primaryLanguage;
  String get secondaryLanguage => _secondaryLanguage;
  List<String> get searchSettings => _searchsettings;

  void updateSearchsettings(String setting) {
    if (!_searchsettings.contains(setting)) {
      _searchsettings.add(setting);
      notifyListeners();
    } else if (_searchsettings.contains(setting)) {
      _searchsettings.remove(setting);
      notifyListeners();
    }
  }

  void addSearchSetting(String setting) {
    if (!_searchsettings.contains(setting)) {
      _searchsettings.add(setting);
      notifyListeners();
    }
  }

  void removeSearchSetting(String setting) {
    if (_searchsettings.contains(setting)) {
      _searchsettings.remove(setting);
      notifyListeners();
    }
  }

  void setPrimaryLanguage(String language) {
    if (_primaryLanguage != language) {
      _primaryLanguage = language;
      notifyListeners();
    }
  }

  void setSecondaryLanguage(String language) {
    if (_secondaryLanguage != language) {
      _secondaryLanguage = language;
      notifyListeners();
    }
  }

  List<String> get preferredLanguages => [_primaryLanguage, _secondaryLanguage];
}
