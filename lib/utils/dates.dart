DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String formatDate(DateTime d) {
  const days = [
    'pondelok', 'utorok', 'streda', 'štvrtok', 'piatok', 'sobota', 'nedeľa',
  ];
  const months = [
    'januára', 'februára', 'marca', 'apríla', 'mája', 'júna',
    'júla', 'augusta', 'septembra', 'októbra', 'novembra', 'decembra',
  ];
  return '${days[d.weekday - 1]} ${d.day}. ${months[d.month - 1]}';
}
