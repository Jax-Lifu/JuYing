import 'package:flutter/material.dart';

import '../../../application/profiles/profile_session.dart';
import '../../../domain/models/child_profile.dart';

class KidsPage extends StatelessWidget {
  const KidsPage({required this.session, super.key});
  final ProfileSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
        children: [
          Text(
            '儿童空间',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '儿童档案、分龄内容、每日时长与独立观看记录。',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 22),
          _ActiveProfileCard(profile: session.activeProfile),
          const SizedBox(height: 28),
          Text(
            '家庭档案列表',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...session.profiles.map((profile) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: session.activeProfile.id == profile.id
                          ? theme.colorScheme.primary.withValues(alpha: 0.5)
                          : theme.colorScheme.outlineVariant,
                      width: session.activeProfile.id == profile.id ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: profile.isChild
                          ? Colors.amber.withValues(alpha: 0.2)
                          : theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      profile.isChild
                          ? Icons.child_care_rounded
                          : Icons.person_rounded,
                      color: profile.isChild
                          ? Colors.amber
                          : theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    profile.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    _profileDescription(profile),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.activeProfile.id == profile.id)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '当前使用',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (profile.isChild)
                        IconButton(
                          tooltip: '删除儿童档案',
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 20),
                          onPressed: () => _deleteChild(context, profile),
                        ),
                      if (session.activeProfile.id != profile.id)
                        const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                  onTap: () => _selectProfile(context, profile),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _addChild(context),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
            label: const Text('新增儿童档案'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 22, color: Colors.grey),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('家长控制',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(height: 2),
                      Text('退出儿童档案和新增档案时要求家长 PIN 验证。',
                          style:
                              TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _profileDescription(FamilyProfile profile) {
    if (!profile.isChild) return '成人档案 · 不受儿童内容和时长限制';
    final child = profile.child!;
    return '${_ageLabel(child.ageBand)} · 每日 ${child.dailyLimitMinutes} 分钟 · ${child.allowedRating}';
  }

  String _ageLabel(ChildAgeBand ageBand) => switch (ageBand) {
        ChildAgeBand.age3to5 => '3–5 岁',
        ChildAgeBand.age6to8 => '6–8 岁',
        ChildAgeBand.age9to12 => '9–12 岁',
        ChildAgeBand.teen => '13 岁以上',
      };

  Future<void> _selectProfile(
    BuildContext context,
    FamilyProfile profile,
  ) async {
    if (profile.id == session.activeProfile.id) return;
    if (!profile.isChild && session.activeProfile.isChild) {
      final authorized = await _authorizeParent(context);
      if (!authorized) return;
    }
    await session.select(profile.id);
  }

  Future<void> _addChild(BuildContext context) async {
    if (!await _authorizeParent(context)) return;
    if (!context.mounted) return;
    final draft = await showDialog<_ChildDraft>(
      context: context,
      builder: (_) => const _AddChildDialog(),
    );
    if (draft == null) return;
    try {
      await session.addChild(
        displayName: draft.name,
        ageBand: draft.ageBand,
        dailyLimitMinutes: draft.dailyLimitMinutes,
      );
    } on ArgumentError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('儿童档案信息不完整')),
        );
      }
    }
  }

  Future<void> _deleteChild(
    BuildContext context,
    FamilyProfile profile,
  ) async {
    if (!await _authorizeParent(context) || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除“${profile.displayName}”吗？'),
        content: const Text('该儿童档案的观看记录、收藏、播放偏好和每日时长将从本机删除。此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await session.deleteChild(profile.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除儿童档案失败，请稍后重试')),
        );
      }
    }
  }

  Future<bool> _authorizeParent(BuildContext context) async {
    final hasPin = await session.hasParentPin();
    if (!context.mounted) return false;
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hasPin ? '输入家长 PIN' : '设置家长 PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: InputDecoration(
            labelText: hasPin ? '4–8 位 PIN' : '输入新的 4–8 位 PIN',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(hasPin ? '验证' : '保存'),
          ),
        ],
      ),
    );
    final pin = controller.text;
    controller.dispose();
    if (accepted != true) return false;
    try {
      if (hasPin) return await session.verifyParentPin(pin);
      await session.setParentPin(pin);
      return true;
    } on ArgumentError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN 必须为 4–8 位数字')),
        );
      }
      return false;
    }
  }
}

class _ActiveProfileCard extends StatelessWidget {
  const _ActiveProfileCard({required this.profile});
  final FamilyProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: profile.isChild
            ? Colors.amber.withValues(alpha: 0.14)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: profile.isChild
              ? Colors.amber.withValues(alpha: 0.35)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: profile.isChild
                ? Colors.amber.withValues(alpha: 0.2)
                : theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
          child: Icon(
            profile.isChild ? Icons.shield_rounded : Icons.person_rounded,
            size: 28,
            color: profile.isChild ? Colors.amber : theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '当前档案：${profile.displayName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: profile.isChild
                          ? Colors.amber.withValues(alpha: 0.2)
                          : theme.colorScheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      profile.isChild ? '儿童模式' : '标准模式',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: profile.isChild
                            ? Colors.amber
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                profile.isChild ? '分龄内容过滤和观看时长策略已生效。' : '成人档案，不受儿童内容和时长策略限制。',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _AddChildDialog extends StatefulWidget {
  const _AddChildDialog();

  @override
  State<_AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends State<_AddChildDialog> {
  final _name = TextEditingController();
  var _ageBand = ChildAgeBand.age6to8;
  var _dailyLimitMinutes = 60;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('新增儿童档案'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '儿童昵称'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ChildAgeBand>(
                initialValue: _ageBand,
                decoration: const InputDecoration(labelText: '年龄段'),
                items: const [
                  DropdownMenuItem(
                      value: ChildAgeBand.age3to5, child: Text('3–5 岁（幼教启蒙）')),
                  DropdownMenuItem(
                      value: ChildAgeBand.age6to8, child: Text('6–8 岁（少儿适龄）')),
                  DropdownMenuItem(
                      value: ChildAgeBand.age9to12, child: Text('9–12 岁（成长探索）')),
                  DropdownMenuItem(
                      value: ChildAgeBand.teen, child: Text('13 岁以上（青少年）')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _ageBand = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _dailyLimitMinutes,
                decoration: const InputDecoration(labelText: '每日观看时长限制'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 分钟')),
                  DropdownMenuItem(value: 45, child: Text('45 分钟')),
                  DropdownMenuItem(value: 60, child: Text('60 分钟（推荐）')),
                  DropdownMenuItem(value: 90, child: Text('90 分钟')),
                  DropdownMenuItem(value: 120, child: Text('120 分钟')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _dailyLimitMinutes = value);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _ChildDraft(
                name: _name.text,
                ageBand: _ageBand,
                dailyLimitMinutes: _dailyLimitMinutes,
              ),
            ),
            child: const Text('创建'),
          ),
        ],
      );
}

class _ChildDraft {
  const _ChildDraft({
    required this.name,
    required this.ageBand,
    required this.dailyLimitMinutes,
  });
  final String name;
  final ChildAgeBand ageBand;
  final int dailyLimitMinutes;
}
