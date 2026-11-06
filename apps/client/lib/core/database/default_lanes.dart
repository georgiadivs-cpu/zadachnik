/// Стабильные ID дорожек по умолчанию. Должны совпадать с сервером,
/// иначе первая синхронизация создаст дубликаты.
abstract final class DefaultLanes {
  static const newLaneId = '00000000-0000-4000-8000-000000000101';
  static const inProgressLaneId = '00000000-0000-4000-8000-000000000102';
  static const reviewLaneId = '00000000-0000-4000-8000-000000000103';
  static const doneLaneId = '00000000-0000-4000-8000-000000000104';

  static const all = <({String id, String name, int sortOrder})>[
    (id: newLaneId, name: 'Новые', sortOrder: 0),
    (id: inProgressLaneId, name: 'В работе', sortOrder: 1),
    (id: reviewLaneId, name: 'Проверка', sortOrder: 2),
    (id: doneLaneId, name: 'Готово', sortOrder: 3),
  ];
}
