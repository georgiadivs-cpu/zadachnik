import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../data/attachment_api.dart';
import '../data/attachment_file_store.dart';
import '../data/attachments_repository.dart';
import '../domain/attachment.dart';
import 'attachment_coordinator.dart';

final attachmentsRepositoryProvider = Provider<AttachmentsRepository>((ref) {
  return AttachmentsRepository(ref.watch(appDatabaseProvider));
});

final attachmentFileStoreProvider = Provider<AttachmentFileStore>((ref) {
  return AppAttachmentFileStore();
});

final attachmentApiProvider = Provider<AttachmentApi>((ref) {
  return DioAttachmentApi();
});

final attachmentCoordinatorProvider = Provider<AttachmentCoordinator>((ref) {
  return AttachmentCoordinator(
    repository: ref.watch(attachmentsRepositoryProvider),
    fileStore: ref.watch(attachmentFileStoreProvider),
    api: ref.watch(attachmentApiProvider),
    sessionResolver: ({bool force = false}) => ref
        .read(authControllerProvider.notifier)
        .ensureFreshSession(force: force),
  );
});

final attachmentsProvider =
    StreamProvider.family<
      List<Attachment>,
      ({AttachmentOwnerType type, String id})
    >((ref, owner) {
      return ref
          .watch(attachmentsRepositoryProvider)
          .watchForOwner(owner.type, owner.id);
    });
