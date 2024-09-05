import 'package:flutter/material.dart';
void showSettingsPopup(BuildContext context,int graphInterval,int packetsLimit,Function(String text,String type) changeSettingParams) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title:const Text('Settings',style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white),),
        backgroundColor:const Color(0xff45474B),
        content:Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Graph Update Interval: ',style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white),),
                Expanded(
                  child: TextFormField(
                    initialValue: '$graphInterval',
                    keyboardType: TextInputType.number,
                    style:const TextStyle(color: Colors.white),
                    onChanged: (value) {
                      changeSettingParams(value,'graphInterval');
                    },
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Packets Limit: ',style: TextStyle(fontWeight: FontWeight.bold,color: Colors.white),),
                SizedBox(
                  width: 75,
                  child: TextFormField(
                    initialValue: '$packetsLimit',
                    keyboardType: TextInputType.number,
                    style:const TextStyle(color: Colors.white),
                    onChanged: (value) {
                      changeSettingParams(value,'packetsLimit');
                    },
                  ),
                ),
              ],
            )
          ],
        ),
        actions: <Widget>[
          TextButton(
            child:const Text('Close',style: TextStyle(color: Colors.white),),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}