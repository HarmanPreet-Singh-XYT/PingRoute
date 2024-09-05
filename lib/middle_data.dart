import 'package:flutter/material.dart';
import 'package:pingroute/graph.dart';

class LeftData extends StatefulWidget {
  const LeftData({super.key,required this.data,required this.isLoading, required this.IPStats, required this.deepStats, required this.interval,required this.isRunning});
  final List<Map<String,dynamic>>? data;
  final bool isLoading;
  final List<Map<String, dynamic>> IPStats;
  final List<Map<String, dynamic>> deepStats;
  final int interval;
  final bool isRunning;
  @override
  State<LeftData> createState() => _LeftDataState();
}

class _LeftDataState extends State<LeftData> {
  String dataType = 'lt';
  setGraphType(String type){
      setState(() {
        dataType = type;
      });
  }
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(minWidth: 1200),
        width: MediaQuery.of(context).size.width*0.9,
        height: MediaQuery.of(context).size.height*0.50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 655),
              clipBehavior: Clip.hardEdge,
              width: MediaQuery.of(context).size.width*0.49,
              height: MediaQuery.of(context).size.height*0.50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(width: 2,color:Colors.blue),
                color:const Color(0xff45474B)
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Flexible(
                        flex: 4, // Adjust the flex value to achieve your desired width
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Hop',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 10,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 100),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'IP',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 12,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 100),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Name',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Min',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Max',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Avg',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(color: Colors.blue, width:2),
                              bottom: BorderSide(color: Colors.blue, width:2),
                            ),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Last',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 55),
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.blue, width:2)),
                          ),
                          child:const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'PL%',
                              style: TextStyle(color: Colors.white, fontSize: 18,fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  (widget.isLoading)
                  ? Center(child: SizedBox(
                    height: MediaQuery.of(context).size.height*0.4,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white,),
                      ],
                    ),
                  ))
                  : Expanded(
                    child: ListView.builder(
                        itemCount: widget.data?.length ?? 0,
                        itemBuilder: (context, index) {
                          final hop = widget.data![index];
                          return Row(
                            children: [
                              Flexible(
                                flex: 4, // Adjust the flex value to achieve your desired width
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${hop['hop']}',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 10,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 100),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${hop['ip']}',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 12,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 100),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${hop['name']}',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.IPStats[index]['min']}ms',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.IPStats[index]['max']}ms',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.IPStats[index]['avg']}ms',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: Colors.blue, width: 1),
                                      bottom: BorderSide(color: Colors.blue, width: 1),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.IPStats[index]['last']}ms',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                              Flexible(
                                flex: 4,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 55),
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.blue, width: 1)),
                                  ),
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${widget.IPStats[index]['pl']}%',
                                      style: const TextStyle(color: Colors.white, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ),
                ],
              ),
            ),
            Container(
              clipBehavior: Clip.hardEdge,
              width: MediaQuery.of(context).size.width*0.4,
              height: MediaQuery.of(context).size.height*0.50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color:const Color(0xff45474B)
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(flex: 1,child: TextButton(onPressed: ()=>setGraphType('pl'), child:Text('Packet Loss',style: TextStyle(color: Colors.white,fontWeight:dataType=='pl' ? FontWeight.bold : FontWeight.normal,fontSize:dataType=='pl' ? 16 : 14),))),
                      Flexible(flex: 1,child: TextButton(onPressed: ()=>setGraphType('lt'), child:Text('Latency',style: TextStyle(color: Colors.white,fontWeight: dataType=='lt' ? FontWeight.bold : FontWeight.normal,fontSize: dataType=='lt' ? 16 : 14)))),
                      Flexible(flex: 1,child: TextButton(onPressed: ()=>setGraphType('jt'), child:Text('Jitter',style: TextStyle(color: Colors.white,fontWeight: dataType=='jt' ? FontWeight.bold : FontWeight.normal,fontSize: dataType=='jt' ? 16 : 14)))),
                      Flexible(flex: 1,child: TextButton(onPressed: ()=>setGraphType('alt'), child:Text('Average Latency',style: TextStyle(color: Colors.white,fontWeight: dataType=='alt' ? FontWeight.bold : FontWeight.normal,fontSize: dataType=='alt' ? 16 : 14)))),
                    ],
                  ),
                  if(widget.deepStats.isNotEmpty) Graph(data:widget.deepStats.last,dataType:dataType,interval: widget.interval,isRunning:widget.isRunning) else widget.isLoading ? Column(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height*0.20,),
                      Center(child: CircularProgressIndicator(color: Colors.white,)),
                    ],
                  ) : Column(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height*0.20,),
                      Center(child: Text('No data available',style: TextStyle(color: Colors.white, fontSize: 20,fontWeight: FontWeight.bold),)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}