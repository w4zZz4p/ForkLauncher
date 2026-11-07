/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Random wallpaper from a folder on the device, changed on a timer.
class LocalSlideshowPanelPage extends StatelessWidget {
  static const String routeName = "local_slideshow_panel";

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        final hasFolder = settings.localSlideshowFolder.isNotEmpty;
        Future<void> pickFolder() async {
          final folder = await _askFolder(context, settings.localSlideshowFolder);
          if (folder != null) await settings.setLocalSlideshowFolder(folder);
        }

        return Column(
          children: [
            SettingsPageHeader(title: localizations.localSlideshow),
            RoundedSwitchListTile(
              autofocus: true,
              title: Text(localizations.localSlideshowEnable),
              secondary: const Icon(Icons.slideshow),
              value: settings.localSlideshowEnabled,
              // Without a folder the switch asks for one instead of enabling a slideshow that cannot run.
              onChanged: (value) async {
                if (!hasFolder) await pickFolder();
                if (settings.localSlideshowFolder.isNotEmpty) await settings.setLocalSlideshowEnabled(value);
              },
            ),
            FocusableSettingsTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(localizations.localSlideshowFolder),
              trailing: Text(hasFolder ? _shortName(settings.localSlideshowFolder) : localizations.unsplashNotSet),
              onPressed: pickFolder,
            ),
            FocusableSettingsTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(localizations.unsplashInterval),
              trailing: Text(localizations.unsplashIntervalMinutes(settings.localSlideshowIntervalMinutes)),
              onPressed: () =>
                  settings.setLocalSlideshowIntervalMinutes(_nextInterval(settings.localSlideshowIntervalMinutes)),
            ),
            if (settings.localSlideshowEnabled)
              FocusableSettingsTile(
                leading: const Icon(Icons.skip_next_outlined),
                title: Text(localizations.localSlideshowNext),
                onPressed: () => context.read<WallpaperService>().advanceLocalSlideshow(),
              ),
          ],
        );
      },
    );
  }

  /// "Pictures/nature_tv" for "/storage/emulated/0/Pictures/nature_tv".
  static String _shortName(String folder) {
    final parts = folder.split('/').where((part) => part.isNotEmpty).toList();
    return parts.length <= 2 ? folder : parts.sublist(parts.length - 2).join('/');
  }

  /// Cycles through [SettingsService.localSlideshowIntervalChoices] on each OK press.
  static int _nextInterval(int current) {
    const choices = SettingsService.localSlideshowIntervalChoices;
    final index = choices.indexOf(current);
    return choices[(index + 1) % choices.length];
  }

  Future<String?> _askFolder(BuildContext context, String current) async {
    final localizations = AppLocalizations.of(context)!;
    final wallpaperService = context.read<WallpaperService>();
    await FLauncherChannel().requestMediaPermissions();
    final folders = await wallpaperService.localImageFolders();
    if (!context.mounted) return null;
    final sorted = folders.keys.toList()..sort((a, b) => _shortName(a).compareTo(_shortName(b)));
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        insetPadding: const EdgeInsets.only(bottom: 120),
        contentPadding: const EdgeInsets.all(24),
        title: Text(localizations.localSlideshowFolder),
        children: [
          if (sorted.isEmpty) Text(localizations.localSlideshowNoImages),
          for (final folder in sorted)
            FocusableSettingsTile(
              autofocus: folder == current || (current.isEmpty && folder == sorted.first),
              leading: Icon(folder == current ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              frameLeading: false,
              title: Text(_shortName(folder)),
              trailing: Text("${folders[folder]}"),
              onPressed: () => Navigator.of(context).pop(folder),
            ),
        ],
      ),
    );
  }
}
