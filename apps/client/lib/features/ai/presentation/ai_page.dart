import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ai_approval_service.dart';
import '../application/ai_providers.dart';
import '../domain/ai_models.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];
  AiProposal? _proposal;
  _ProposalState _state = _ProposalState.proposed;
  String? _statusMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        text:
            'Я локальный ассистент «Ежедневника». Готовлю предложения '
            'изменений, но применяю их только после подтверждения.',
        fromUser: false,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) {
      return;
    }
    _controller.clear();
    setState(() {
      _busy = true;
      _statusMessage = null;
      _messages.add(_ChatMessage(text: text, fromUser: true));
    });
    _scrollToBottom();
    try {
      final response = await ref.read(aiAssistantProvider).respond(text);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_ChatMessage(text: response.message, fromUser: false));
        if (response.proposal != null) {
          _proposal = response.proposal;
          _state = _ProposalState.proposed;
        }
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatMessage(
            text: 'Не удалось обработать запрос: $error',
            fromUser: false,
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _approve() async {
    final proposal = _proposal;
    if (proposal == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    final result = await ref.read(aiApprovalServiceProvider).approve(proposal);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (result.success) {
        _state = _ProposalState.applied;
        _statusMessage = result.message;
      } else if (result.stale) {
        _state = _ProposalState.stale;
        _statusMessage = result.message;
      } else {
        _state = _ProposalState.failed;
        _statusMessage = result.message;
      }
      _messages.add(
        _ChatMessage(
          text: result.message,
          fromUser: false,
          isError: !result.success,
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _reject() async {
    final proposal = _proposal;
    if (proposal == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    await ref.read(aiApprovalServiceProvider).reject(proposal);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _state = _ProposalState.rejected;
      _statusMessage = 'Предложение отклонено, данные не изменены.';
      _messages.add(
        const _ChatMessage(
          text: 'Предложение отклонено, данные не изменены.',
          fromUser: false,
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI-ассистент'),
        actions: [
          IconButton(
            key: const Key('aiJournalButton'),
            tooltip: 'Журнал AI',
            onPressed: () => _showJournal(context),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            key: const Key('aiPrivacyButton'),
            tooltip: 'Приватность AI',
            onPressed: () => _showPrivacy(context),
            icon: const Icon(Icons.shield_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final chat = _ChatPanel(
            messages: _messages,
            controller: _controller,
            scrollController: _scrollController,
            busy: _busy,
            onSend: _send,
            proposal: wide ? null : _buildProposal(),
          );
          if (!wide) {
            return chat;
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: chat),
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              SizedBox(
                width: 430,
                child: _SidePanel(
                  proposal: _buildProposal(),
                  journal: ref.watch(aiJournalProvider),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProposal() {
    final proposal = _proposal;
    if (proposal == null) {
      return const _EmptyProposal();
    }
    return _ProposalCard(
      proposal: proposal,
      status: _state,
      statusMessage: _statusMessage,
      busy: _busy,
      onApprove: _approve,
      onReject: _reject,
    );
  }

  Future<void> _showJournal(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _JournalSheet(journal: ref.watch(aiJournalProvider)),
    );
  }

  Future<void> _showPrivacy(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _PrivacySheet(),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.controller,
    required this.scrollController,
    required this.busy,
    required this.onSend,
    required this.proposal,
  });

  final List<_ChatMessage> messages;
  final TextEditingController controller;
  final ScrollController scrollController;
  final bool busy;
  final VoidCallback onSend;
  final Widget? proposal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Approval mode · изменения применяются только после подтверждения',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length + (proposal == null ? 0 : 1),
            itemBuilder: (context, index) {
              if (index < messages.length) {
                return _Bubble(message: messages[index]);
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: proposal,
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('aiPromptField'),
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Попросите изменить данные…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('aiSendButton'),
                  onPressed: busy ? null : onSend,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Отправить'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = message.fromUser
        ? scheme.primary
        : message.isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = message.fromUser
        ? scheme.onPrimary
        : message.isError
        ? scheme.onErrorContainer
        : scheme.onSurface;
    return Align(
      alignment: message.fromUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.proposal, required this.journal});

  final Widget proposal;
  final AsyncValue<List<AiJournalEntry>> journal;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        proposal,
        const SizedBox(height: 20),
        Text('Журнал AI', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _JournalList(journal: journal),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.status,
    required this.statusMessage,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final AiProposal proposal;
  final _ProposalState status;
  final String? statusMessage;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decided = status != _ProposalState.proposed;
    return Card(
      key: const Key('aiProposalCard'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    proposal.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text(proposal.explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            for (final change in proposal.changes) _ChangeRow(change: change),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Последствия: ${proposal.impact}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            if (statusMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                statusMessage!,
                key: const Key('aiStatusMessage'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  key: const Key('aiRejectButton'),
                  onPressed: decided || busy ? null : onReject,
                  child: const Text('Отклонить'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('aiApproveButton'),
                  onPressed: decided || busy ? null : onApprove,
                  child: const Text('Подтвердить'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              decided
                  ? 'Решение зафиксировано в журнале.'
                  : 'Данные не изменены до подтверждения.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final AiChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${change.targetTitle} · ${change.field}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  change.before,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 14),
              ),
              Flexible(
                child: Text(
                  change.after,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _ProposalState status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      _ProposalState.proposed => ('Не применено', scheme.tertiaryContainer),
      _ProposalState.applied => ('Применено', scheme.primaryContainer),
      _ProposalState.rejected => ('Отклонено', scheme.errorContainer),
      _ProposalState.stale => ('Устарело', scheme.errorContainer),
      _ProposalState.failed => ('Ошибка', scheme.errorContainer),
    };
    return Container(
      key: const Key('aiStatusChip'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _EmptyProposal extends StatelessWidget {
  const _EmptyProposal();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text('Предложений пока нет', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Опишите изменение в чате. Здесь появится точный diff '
              'и кнопки подтверждения.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalList extends StatelessWidget {
  const _JournalList({required this.journal});

  final AsyncValue<List<AiJournalEntry>> journal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return journal.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Журнал недоступен: $error'),
      data: (entries) {
        if (entries.isEmpty) {
          return Text('Журнал пуст.', style: theme.textTheme.bodySmall);
        }
        return Column(
          children: [
            for (final entry in entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  switch (entry.status) {
                    'APPLIED' => Icons.check_circle,
                    'REJECTED' => Icons.cancel,
                    'STALE' => Icons.warning_amber,
                    'FAILED' => Icons.error,
                    _ => Icons.pending_outlined,
                  },
                  color: switch (entry.status) {
                    'APPLIED' => theme.colorScheme.primary,
                    'REJECTED' => theme.colorScheme.error,
                    'STALE' => theme.colorScheme.tertiary,
                    'FAILED' => theme.colorScheme.error,
                    _ => theme.colorScheme.outline,
                  },
                ),
                title: Text(entry.title),
                subtitle: Text(
                  '${_statusLabel(entry.status)} · '
                  '${_formatTime(entry.createdAt)}',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _JournalSheet extends StatelessWidget {
  const _JournalSheet({required this.journal});

  final AsyncValue<List<AiJournalEntry>> journal;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Журнал AI', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: _JournalList(journal: journal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Приватность AI', style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text(
              'Провайдер: локальный rule-based режим. '
              'Запросы не отправляются во внешние сервисы, ключи не нужны.',
            ),
            const SizedBox(height: 10),
            const Text(
              'AI не получает прямой доступ к базе данных, shell или '
              'файловой системе. Доступны только ограниченные инструменты: '
              'задачи, даты, напоминания и заметки.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Содержимое заметок и вложений считается данными, а не '
              'командами. Любое изменение применяется только после '
              'подтверждения и записывается в журнал.',
            ),
            const SizedBox(height: 12),
            Text(
              'Синхронизация журнала AI не выполняется.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProposalState { proposed, applied, rejected, stale, failed }

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.fromUser,
    this.isError = false,
  });

  final String text;
  final bool fromUser;
  final bool isError;
}

String _statusLabel(String status) {
  return switch (status) {
    'APPLIED' => 'Применено',
    'REJECTED' => 'Отклонено',
    'STALE' => 'Устарело',
    'FAILED' => 'Ошибка',
    _ => 'Ожидает решения',
  };
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
