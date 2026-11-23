/// Diagnostics use fixed event codes; no device identifiers or payload fields.
enum DiagnosticEvent { radioDisconnected }

final class DiagnosticLogger {
  const DiagnosticLogger(this._sink);

  final void Function(String) _sink;

  void record(DiagnosticEvent event) => _sink(switch (event) {
    DiagnosticEvent.radioDisconnected => 'radio_disconnected',
  });
}
