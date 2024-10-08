import 'package:flutter/material.dart';
import 'package:PingRoute/graph.dart';

class BottomData extends StatefulWidget {
  const BottomData({
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
    required this.toggleStatistics
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

  @override
  State<BottomData> createState() => _BottomDataState();
}

class _BottomDataState extends State<BottomData> {
  String dataType = 'pl';
  int selectedHop = 1;

  void setGraphType(String type) {
    setState(() {
      dataType = type;
    });
  }
  void setHop(int hop){
    setState(() {
      selectedHop = hop;
    });
  }

  @override
  Widget build(BuildContext context) {
    return (widget.dataCollected && widget.success) ? Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Scrollable list of buttons
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.1,
          height: MediaQuery.of(context).size.height * 0.4,// Set height to allow scrolling
          child: SingleChildScrollView(
            child: Column(
              children: widget.deepStats.map((item) {
                return Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                  },
                  border: TableBorder.all(color: Colors.blue, width: 1),
                  children: [
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                            onPressed: () {
                              // Define your action here
                              setHop(item['hop']);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('${item['hop']}',style:TextStyle(fontWeight:item['hop']==selectedHop ? FontWeight.bold : FontWeight.normal),),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        // Table with statistics
        SizedBox(
          width: MediaQuery.of(context).size.width * 0.32,
          height: MediaQuery.of(context).size.height * 0.4, // Adjust height to fit content
          child: SingleChildScrollView(
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
                    _buildTableRow('Jitter', '${widget.deepStats[selectedHop-1]['jitter'].last['value']}ms'),
                    _buildTableRow('Latency', '${widget.deepStats[selectedHop-1]['pings'].last['value']}ms'),
                    _buildTableRow('Minimum', '${widget.IPStats[selectedHop-1]['min']}ms'),
                    _buildTableRow('IP Address', '${widget.IPStats[selectedHop-1]['ip']}'),
                    _buildTableRow('Maximum', '${widget.IPStats[selectedHop-1]['max']}ms'),
                    _buildTableRow('Packet Loss', '${widget.deepStats[selectedHop-1]['pl'].last['value']}%'),
                    _buildTableRow('Domain Name', '${widget.IPStats[selectedHop-1]['name']}'),
                    _buildTableRow('Average Latency', '${widget.deepStats[selectedHop-1]['avg'].last['value']}ms'),
                    _buildTableRow('Total Packets Sent/Received', '${widget.IPStats[selectedHop-1]['sentPackets']}/${widget.IPStats[selectedHop-1]['receivedPackets']}'),
                    _buildTableRow('Total Packets', '${widget.totalPackets}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Graph
        
        if (widget.deepStats.isNotEmpty)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.38,
            height: MediaQuery.of(context).size.height * 0.4,
            child: Graph(
              data: widget.deepStats[selectedHop-1],
              dataType: dataType,
              interval: widget.interval,
              isRunning: widget.isRunning,
            ),
          ),
          SizedBox(
          width: MediaQuery.of(context).size.width * 0.1,
          height: MediaQuery.of(context).size.height * 0.4,// Set height to allow scrolling
          child: SingleChildScrollView(
            child: Column(
              children:[ 
                const SizedBox(height: 10,),
                ElevatedButton(
                  onPressed: () {
                    // Define your action here
                    widget.toggleStatistics();
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16 ,horizontal: 10),
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:const Text('View All Hops',style:TextStyle(fontWeight:FontWeight.bold),textAlign: TextAlign.center,),
                ),
                const SizedBox(height: 10,),
                Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                  },
                  border: TableBorder.all(color: Colors.blueAccent, width: 1,borderRadius:const BorderRadius.only(bottomLeft: Radius.circular(20),topLeft: Radius.circular(20))),
                  children: [
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton(
                            onPressed: () {
                              // Define your action here
                              setGraphType('jt');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Jitter',style:TextStyle(fontWeight:dataType == 'jt' ? FontWeight.bold : FontWeight.normal)),
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
                              // Define your action here
                              setGraphType('lt');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Latency',style:TextStyle(fontWeight:dataType == 'lt' ? FontWeight.bold : FontWeight.normal)),
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
                              // Define your action here
                              setGraphType('pl');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Packet Loss',style:TextStyle(fontWeight:dataType == 'pl' ? FontWeight.bold : FontWeight.normal)),
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
                              // Define your action here
                              setGraphType('alt');
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Average Latency',style:TextStyle(fontWeight:dataType == 'alt' ? FontWeight.bold : FontWeight.normal),textAlign: TextAlign.center,),
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
    ) : widget.isLoading ? const Center(child: CircularProgressIndicator(color: Colors.white,)) : const Center(child: Text('No data available',style: TextStyle(color: Colors.white, fontSize: 20,fontWeight: FontWeight.bold),));
  }

  TableRow _buildTableRow(String label, String value) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
