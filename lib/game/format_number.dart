const List<String> _suffixes = [
  'K',
  'M',
  'B',
  'T',
  'q',
  'Q',
  's',
  'S',
  'o',
  'N',
  'd',
  'U',
  'D',
  'Td',
];

/// Formats a value with three significant figures and the project's suffixes.
String formatNumber(double value, {bool scientific = false}) {
  if (value == 0) {
    return '0';
  }
  if (!value.isFinite) {
    return value.toString();
  }
  if (scientific) {
    return value.toStringAsExponential(2);
  }

  final absoluteValue = value.abs();
  if (absoluteValue < 1000) {
    final formatted = _formatThreeSignificantFigures(value);
    if (double.parse(formatted).abs() < 1000) {
      return formatted;
    }
  }

  var scaled = value;
  var suffixIndex = 0;
  while (scaled.abs() >= 1000 && suffixIndex < _suffixes.length) {
    scaled /= 1000;
    suffixIndex++;
  }
  suffixIndex--;
  if (suffixIndex >= _suffixes.length) {
    return value.toStringAsExponential(2);
  }

  var rounded = _formatThreeSignificantFigures(scaled);
  if (double.parse(rounded).abs() >= 1000) {
    suffixIndex++;
    if (suffixIndex >= _suffixes.length) {
      return value.toStringAsExponential(2);
    }
    scaled /= 1000;
    rounded = _formatThreeSignificantFigures(scaled);
  }

  return '$rounded${_suffixes[suffixIndex]}';
}

String _formatThreeSignificantFigures(double value) {
  return value.toStringAsPrecision(3);
}
