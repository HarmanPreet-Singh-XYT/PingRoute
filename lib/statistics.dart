import 'package:PingRoute/graph.dart';
import 'package:flutter/material.dart';

class Statistics extends StatefulWidget {
  const Statistics({
    super.key,
    required this.IPStats,
    required this.deepStats,
    required this.interval,
    required this.isRunning,
    required this.graphInterval,
    required this.isLoading,
    required this.totalPackets,
    required this.dataCollected,
    required this.success,
    required this.toggleStatistics,
    required this.dataTypes,
    required this.setDataType,
    });
  final List<Map<String, dynamic>> IPStats;
  final List<Map<String, dynamic>> deepStats;
  final int totalPackets;
  final int graphInterval;
  final bool isLoading;
  final int interval;
  final bool isRunning;
  final bool dataCollected;
  final bool success;
  final Function() toggleStatistics;
  final Function(int index,String type) setDataType;
  final List<Map<String, dynamic>> dataTypes;

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            child: Column(
              children: [
                // Navbar widget, assuming you can modify it to include a settings button or use an external button
                Container(
                  constraints:const BoxConstraints(minWidth: 1100,minHeight: 60),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue,width: 2),
                    borderRadius: BorderRadius.circular(20)
                  ),
                  clipBehavior: Clip.hardEdge,
                  width: MediaQuery.of(context).size.width*0.95,
                  child: Container(
                    height: MediaQuery.of(context).size.height*0.85,
                    decoration:const BoxDecoration(
                      color: Color(0xff45474B),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const SizedBox(height: 60,),
                            ElevatedButton(
                              onPressed: () {
                                // Define your action here
                                widget.toggleStatistics();
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16,horizontal: 5),
                                textStyle: const TextStyle(fontSize: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child:const Text('Close',style:TextStyle(fontWeight:FontWeight.bold),),
                            ),
                            const SizedBox(width: 10,),
                          ],
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).size.height*0.75,
                          width: MediaQuery.of(context).size.width*0.9,
                          child: SingleChildScrollView(
                            child: Column(
                              children: widget.deepStats.asMap().entries.map((entry) {
                                int index = entry.key;
                                var deepStat = entry.value;
                                var ipStat = widget.IPStats[index];
                            
                            
                                return Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Table with statistics
                                        SizedBox(
                                          width: MediaQuery.of(context).size.width * 0.32,
                                          height: 440, // Adjust height to fit content
                                          child: Column(
                                            children: [
                                              Table(
                                                columnWidths: const {
                                                  1: FlexColumnWidth(1),
                                                  2: FlexColumnWidth(2),
                                                },
                                                border: TableBorder.all(
                                                  color: Colors.blue,
                                                  width: 1,
                                                ),
                                                children: [
                                                  _buildTableRow('Hop', '${index+1}'),
                                                  _buildTableRow('Jitter', '${deepStat['jitter'].last['value']}ms'),
                                                  _buildTableRow('Latency', '${deepStat['pings'].last['value']}ms'),
                                                  _buildTableRow('Minimum', '${ipStat['min']}ms'),
                                                  _buildTableRow('IP Address', '${ipStat['ip']}'),
                                                  _buildTableRow('Maximum', '${ipStat['max']}ms'),
                                                  _buildTableRow('Packet Loss', '${deepStat['pl'].last['value']}%'),
                                                  _buildTableRow('Domain Name', '${ipStat['name']}'),
                                                  _buildTableRow('Average Latency', '${deepStat['avg'].last['value']}ms'),
                                                  _buildTableRow('Total Packets Sent/Received', '${ipStat['sentPackets']}/${ipStat['receivedPackets']}'),
                                                  _buildTableRow('Total Packets', '${widget.totalPackets}'),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        
                                        // Graph
                                        if (widget.deepStats.isNotEmpty)
                                          SizedBox(
                                            width: MediaQuery.of(context).size.width * 0.48,
                                            height: 400,
                                            child: Graph(
                                              data: deepStat,
                                              dataType: widget.dataTypes[index]['dataType'],
                                              interval: widget.interval,
                                              isRunning: widget.isRunning,
                                            ),
                                          ),
                                          
                                        SizedBox(
                                          width: MediaQuery.of(context).size.width * 0.1,
                                          height: 400, // Set height to allow scrolling
                                          child: SingleChildScrollView(
                                            child: Column(
                                              children: [
                                                Table(
                                                  columnWidths: const {
                                                    0: FlexColumnWidth(1),
                                                  },
                                                  border: TableBorder.all(
                                                    color: Colors.blueAccent,
                                                    width: 1,
                                                    borderRadius: const BorderRadius.all(Radius.circular(20))
                                                  ),
                                                  children: [
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.all(8.0),
                                                          child: ElevatedButton(
                                                            onPressed: () {
                                                              widget.setDataType(index, 'jt');
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                                              textStyle: const TextStyle(fontSize: 16),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Jitter',
                                                              style: TextStyle(
                                                                fontWeight: widget.dataTypes[index]['dataType'] == 'jt' ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.all(8.0),
                                                          child: ElevatedButton(
                                                            onPressed: () {
                                                              widget.setDataType(index, 'lt');
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                                              textStyle: const TextStyle(fontSize: 16),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Latency',
                                                              style: TextStyle(
                                                                fontWeight: widget.dataTypes[index]['dataType'] == 'lt' ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.all(8.0),
                                                          child: ElevatedButton(
                                                            onPressed: () {
                                                              widget.setDataType(index, 'pl');
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                                              textStyle: const TextStyle(fontSize: 16),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Packet Loss',
                                                              style: TextStyle(
                                                                fontWeight: widget.dataTypes[index]['dataType'] == 'pl' ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    TableRow(
                                                      children: [
                                                        Padding(
                                                          padding: const EdgeInsets.all(8.0),
                                                          child: ElevatedButton(
                                                            onPressed: () {
                                                              widget.setDataType(index, 'alt');
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                                              textStyle: const TextStyle(fontSize: 16),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Average Latency',
                                                              style: TextStyle(
                                                                fontWeight: widget.dataTypes[index]['dataType'] == 'alt' ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                              textAlign: TextAlign.center,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(color: Colors.blue,),
                                    const SizedBox(height: 10,)
                                  ],
                                );
                              }).toList(), // Converts the map to a list of widgets
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    
        ],
      );
  }
  TableRow _buildTableRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,  // Enable horizontal scrolling
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
              overflow: TextOverflow.visible,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,  // Enable horizontal scrolling
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
              overflow: TextOverflow.visible,  // Ensure overflow is visible to trigger scrolling
            ),
          ),
        ),
      ],
    );
  }
}