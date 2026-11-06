enum WidgetDestination { home, parking }

/// Widget links only navigate. They carry no vehicle, credentials, or save data.
WidgetDestination? parseWidgetLink(Uri uri) {
  if (uri.scheme != 'carcar' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return switch (uri.host) {
    'home' => WidgetDestination.home,
    'parking' => WidgetDestination.parking,
    _ => null,
  };
}
