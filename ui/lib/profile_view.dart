import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import 'avatar_image.dart';
import 'http.dart';
import 'me_model.dart';
import 'profile_form.dart';

class ProfileView extends StatelessWidget {
  ProfileView({Key? key}) : super(key: key);

  final HttpService httpService = HttpService();

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your account and avatar. Rooms that end up with no meaningful membership left may also disappear.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await httpService.delete_account();
      Provider.of<MeModel>(context, listen: false).reset();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Consumer<MeModel>(
        builder: (context, me, child) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      child: AvatarImage(
                        picture: me.data?['picture'],
                        radius: 64,
                      ),
                    ),
                    Container(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        child: const Text('Upload picture'),
                        onPressed: () async {
                          FilePickerResult? result = await FilePicker.platform
                              .pickFiles();
                          if (result != null) {
                            final file = result.files.single.bytes!;
                            final data = await httpService
                                .upload_profile_picture(file);
                            Provider.of<MeModel>(
                              context,
                              listen: false,
                            ).set_profile_picture(data['picture']);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile picture saved'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                ProfileForm(data: me.data),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _deleteAccount(context),
                    child: const Text('Delete account'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
