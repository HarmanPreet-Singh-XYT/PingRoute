import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'navbar.dart';
import 'middle_data.dart';
import 'network.dart';
import 'parse_result.dart';
import 'package:validators/validators.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:intl/intl.dart';
void main(){
  runApp(
    const MaterialApp(
      home:MainApp(),
      color:Color(0xffF5F7F8),
    )
  );
}
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}
final networkLib = NetworkLib();
Future<List<String>> runHeavyTaskIWithIsolate(String ip) async {
  final ReceivePort receivePort = ReceivePort();
  List<String> result = [];
  try {
    await Isolate.spawn(useIsolate, [receivePort.sendPort,ip]);
    result = await receivePort.first;
  } on Object catch (e, stackTrace) {
    debugPrint('Isolate Failed: $e');
    debugPrint('Stack Trace: $stackTrace');
    receivePort.close();
  }
  return result;
}

void useIsolate(List<dynamic> args) async {
  SendPort resultPort = args[0];
  final value = networkLib.performTraceroute(args[1]);
  resultPort.send(value);
}
// Future<List<int>> runPings(List<Map<String, dynamic>> ipStats) async {
//   final ReceivePort receivePort = ReceivePort();
//   List<int> result = [];
//   try {
//     await Isolate.spawn(useIsolatePing, [receivePort.sendPort,ipStats]);
//     result = await receivePort.first;
//   } on Object catch (e, stackTrace) {
//     debugPrint('Isolate Failed: $e');
//     debugPrint('Stack Trace: $stackTrace');
//     receivePort.close();
//   }
//   return result;
// }

// void useIsolatePing(List<dynamic> args) async {
//   SendPort resultPort = args[0];
//   List<int> results = [];
//   for (int x = 0; x < args[1].length; x++) {
//     final ping = networkLib.performPing(args[1][x]['ip']);
//     // Process the ping result if needed
//     results.add(ping);
//   }
//   resultPort.send(results);
// }
double calculateJitter(List<Map<String, dynamic>> hops) {
  if (hops.length < 2) {
    // Not enough data to calculate jitter
    return 0.0;
  }

  // Extract values from hops
  List values = hops.map((hop) => hop['value'].toDouble()).toList();

  // Calculate delay differences
  List<double> delays = [];
  for (int i = 1; i < values.length; i++) {
    delays.add((values[i] - values[i - 1]).abs());
  }

  // Calculate average jitter
  double jitter = delays.isNotEmpty
      ? delays.reduce((a, b) => a + b) / delays.length
      : 0.0;

  return jitter;
}
String getCurrentTime() {
  final now = DateTime.now();
  final formattedTime = DateFormat('mm:ss').format(now);
  return formattedTime;
}


class _MainAppState extends State<MainApp> {
  String ip = '1.1.1.1';
  int interval = 1000;
  int graphInterval = 1000;
  List<Map<String, dynamic>>? tracerouteResult;
  bool isLoading = false;
  bool isRunning = false;
  List<Map<String, dynamic>> ipStats = [];
  List<Map<String, dynamic>> deepStats = [];
  String currentTime = getCurrentTime();
  int totalPackets = 0;
  int packetsLimit = 25;
  
  Future<void> _performTraceroute() async {
    if (isIP(ip)||isURL(ip)) {
      setRunning(true);
      setLoading();
      ipStats = [];
      deepStats = [];
      final result = await runHeavyTaskIWithIsolate(ip);
      // Parse the result
      List<Map<String, dynamic>> parsedList = parseArrayOfStrings(result);
      for(int x =0; x<parsedList.length;x++){
        ipStats.add({'hop':parsedList[x]['hop'],'ip':parsedList[x]['ip'] ,'max':parsedList[x]['ping'],'min':parsedList[x]['ping'],'last':parsedList[x]['ping'],'avg':parsedList[x]['ping'],'pl':0});
        deepStats.add({'hop':parsedList[x]['hop'],'avg':<Map<String,dynamic>>[{'time':getCurrentTime(),'value':parsedList[x]['ping']}],'pl':<Map<String,dynamic>>[{'time':getCurrentTime(),'value':0}],'jitter':<Map<String,dynamic>>[{'time':getCurrentTime(),'value':1}],'pings':<Map<String,dynamic>>[{'time':getCurrentTime(),'value':parsedList[x]['ping']}]});
        totalPackets = 1;
      }
      setState(() {
        tracerouteResult = parsedList;
      });
      setLoading();
    }
  }
  Future<void> runPingsWithDelay(bool initialIsRunning, List<Map<String, dynamic>> ipStats, int interval) async {
   bool currentIsRunning = initialIsRunning;
   String time = currentTime;
   while (currentIsRunning && ipStats.isNotEmpty) {
     currentIsRunning = isRunning;
    time = getCurrentTime();
     
     if(!currentIsRunning) break;
     
     List<Future<int>> pingFutures = [];
     
     for (int x = 0; x < ipStats.length; x++) {
       pingFutures.add(
         Ping(ipStats[x]['ip'], count: 1, interval: 0).stream.first.then((result) {
           try {
             return result.response?.time?.inMilliseconds ?? -1;
           } catch (e) {
             return -1;
           }
         })
       );
     }

     List<int> tempPings = await Future.wait(pingFutures);
     //update values
     for(int y = 0; y < tempPings.length; y++){
       if(totalPackets < packetsLimit) totalPackets+=1;
       deepStats[y]['pings'].add({'time':time,'value':tempPings[y]});
        
       // Update max and min values
       if (tempPings[y] > ipStats[y]['max'] && tempPings[y] != -1) {
         ipStats[y]['max'] = tempPings[y];
       }
       if (tempPings[y] < ipStats[y]['min'] && tempPings[y] != -1) {
         ipStats[y]['min'] = tempPings[y];
       }

       ipStats[y]['last'] = tempPings[y];
      int validPacketloss = 0;

      // Count the number of lost packets
      deepStats[y]['pings'].forEach((each) {
        if (each['value'] == -1) {
          validPacketloss++;
        }
      });

      // Calculate packet loss percentage
      int calculatedPL = (validPacketloss * 100 / totalPackets).round();

      // Update deepStats and ipStats
      deepStats[y]['pl'].add({'time': time, 'value': calculatedPL});
      ipStats[y]['pl'] = calculatedPL;
         // Calculate average excluding -1 values
       num totalAVG = 0;
        int count = 0;
       deepStats[y]['pings'].forEach((each) {
         if (each['value'] != -1) {
           totalAVG += each['value'];
           count++;
         }
       });
       num avgPing = (totalAVG/count).round();
       
       setState(() {
         ipStats[y]['avg'] = avgPing;
       });

       if(deepStats[y]['pl'].length > 25) deepStats[y]['pl'].removeAt(0);
       if(deepStats[y]['jitter'].length > 25) deepStats[y]['jitter'].removeAt(0);
       if(deepStats[y]['pings'].length > 25) deepStats[y]['pings'].removeAt(0);
       if(deepStats[y]['avg'].length > 25) deepStats[y]['avg'].removeAt(0);
     }
     await Future.delayed(Duration(milliseconds: interval));
   }
 }

  void setLoading(){
    setState(() {
      isLoading = !isLoading;
    });
  }
  void setRunning(bool input){
    if(!isLoading){
      setState(() {
        isRunning = input;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    void setText(String text,String type){
      switch (type) {
        case 'ip':
            ip = text;
          break;
        case 'interval':
          if(isNumeric(text)){
            int convertedString = int.parse(text);
            interval = convertedString;
          }
          break;
      }
    }
    void execTraceroute()async{
      if(isRunning){
        setRunning(false);
      }else{
        await _performTraceroute();
        runPingsWithDelay(isRunning,ipStats,interval);
      }
    }
    return Scaffold(
      body: Column(
        children: [
          Navbar(setText: setText,execTraceroute:execTraceroute,isRunning: isRunning,),
          SizedBox(height: MediaQuery.of(context).size.height*0.02,),
          LeftData(data: tracerouteResult,isLoading: isLoading,IPStats:ipStats,deepStats:deepStats,interval:graphInterval,isRunning:isRunning),
        ],
      ),
    );
  }
}