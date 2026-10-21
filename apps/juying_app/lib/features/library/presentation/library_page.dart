import 'package:flutter/material.dart';

import 'package:juying/features/nas/presentation/nas_page.dart';

/// Unified Media Library Explorer (Section 6.1 features/library).
///
/// **What**: Provides local and network-attached storage (SMB, WebDAV, NFS) media browsing.
///
/// **Why**: Implements Section 6.1 `features/library/` directory specification,
/// consolidating local file browsing and NAS protocol streaming into a cohesive library domain.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NasPage();
  }
}
