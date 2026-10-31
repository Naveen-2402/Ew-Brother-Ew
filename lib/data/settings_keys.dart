/// Keys of the `settings` table. MUST match android/.../data/Keys.kt.
/// Defaults live on the native side (inserted when the database is created/opened).
class SettingsKeys {
  const SettingsKeys._();

  static const monitorOn = 'monitor_on';
  static const bubbleOn = 'bubble_on';
  static const bubbleSize = 'bubble_size';
  static const bubbleX = 'bubble_x';
  static const bubbleY = 'bubble_y';
  static const intervalInstagram = 'interval_instagram';
  static const intervalYoutube = 'interval_youtube';
  static const pauseSeconds = 'pause_seconds';
  static const limitOn = 'limit_on';
  static const limitReels = 'limit_reels';
  static const limitAction = 'limit_action';
  static const dayResetHour = 'day_reset_hour';
  static const dayResetNext = 'day_reset_next';
  static const dayResetNextAfter = 'day_reset_next_after';
  static const messages = 'pause_messages';
  static const interruptOn = 'interrupt_on';
  static const focusOn = 'focus_on';
  static const focusStart = 'focus_start';
  static const focusEnd = 'focus_end';
  static const focusApps = 'focus_apps';
  static const statusNotifOn = 'status_notif_on';
  static const morningOn = 'morning_on';
  static const morningTime = 'morning_time';
  static const eveningOn = 'evening_on';
  static const eveningTime = 'evening_time';
  static const weeklyOn = 'weekly_on';
  static const theme = 'theme';
  static const extraReelIds = 'extra_reel_ids';
}
