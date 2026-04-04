import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'http.dart';
import 'me_model.dart';

class NavDrawer extends StatelessWidget {
  final HttpService httpService = HttpService();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Rooms'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/rooms');
            },
          ),
          ListTile(
            leading: const Icon(Icons.input),
            title: const Text('Sign Out'),
            onTap: () async {
              await httpService.signout();
              Provider.of<MeModel>(context, listen: false).reset();
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
    );
  }
}
