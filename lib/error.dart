import 'package:flutter/material.dart';
void showErrorPopup(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title:const Row(
          children: [
            Icon(Icons.error, color: Colors.red),  // Error icon
            SizedBox(width: 8),
            Text('Error',style: TextStyle(fontWeight: FontWeight.bold),),
          ],
        ),
        content:const Text('Please check your network connection.',style: TextStyle(fontWeight: FontWeight.w600),),
        actions: <Widget>[
          TextButton(
            child:const Text('Close'),
            onPressed: () {
              Navigator.of(context).pop();  // Close the popup
            },
          ),
        ],
      );
    },
  );
}
