import 'package:flutter/material.dart';
class Navbar extends StatelessWidget {
  const Navbar({super.key,required this.setText,required this.execTraceroute,required this.isRunning,required this.showSettings});
  final Function(String text,String type) setText;
  final Function() execTraceroute;
  final bool isRunning;
  final Function() showSettings;
  @override
  Widget build(BuildContext context) {
    return Center(
        child: Container(
          constraints:const BoxConstraints(minWidth: 1100,minHeight: 60),
          width: MediaQuery.of(context).size.width*0.99,
          
          child: Container(
            height: MediaQuery.of(context).size.height*0.08,
            decoration:const BoxDecoration(
              color: Color(0xff45474B),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20),bottomRight: Radius.circular(20))
            ),
            child:Center(
              child: SizedBox(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      child: Row(
                        children: [
                          // ElevatedButton(
                          //   onPressed: ()=>widget.execTraceroute(),
                          //   child: Text('Execute'),
                          //   // child: Container(
                          //   //   margin:const EdgeInsets.symmetric(horizontal: 10),
                          //   //   decoration:BoxDecoration(
                          //   //     borderRadius: BorderRadius.circular(100),
                          //   //     color:const Color(0xffF5F7F8)
                          //   //   ),
                          //   //   height:50,
                          //   //   width: 50,
                          //   // ),
                          // ),
                          IconButton(
                            onPressed: ()=>execTraceroute(),
                             icon:Icon(isRunning ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,color:isRunning ? const Color(0xffF4CE14) : const Color(0xff379777),size: 50,)),
                          const SizedBox(width: 20,),
                          Row(
                            children: [
                              const Text('Target Name/IP',style: TextStyle(fontWeight: FontWeight.bold,fontSize: 16,color: Colors.white)),
                              const SizedBox(width: 20,),
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15)
                                ),
                                width: 200,
                                padding:const EdgeInsets.symmetric(horizontal: 20),
                                child:TextFormField(
                                  onChanged:(text) {
                                    setText(text,'ip');
                                  },
                                  style:const TextStyle(fontSize: 18),
                                  textAlign: TextAlign.center,
                                  initialValue: '1.1.1.1',
                                  decoration:const InputDecoration(
                                    hintText: 'IP/Domain',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40,),
                              const Text('Time Interval',style: TextStyle(fontWeight: FontWeight.bold,fontSize: 16,color: Colors.white)),
                              const SizedBox(width: 20,),
                              Container(
                                height: 40,
                                margin:const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15)
                                ),
                                width: 100,
                                padding:const EdgeInsets.symmetric(horizontal: 20),
                                child:TextFormField(
                                  onChanged:(text) {
                                    setText(text,'interval');
                                  },
                                  style:const TextStyle(fontSize: 18),
                                  initialValue: '1000',
                                  textAlign: TextAlign.center,
                                  decoration:const InputDecoration(
                                    hintText: 'Milliseconds',
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 40,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text('ms',style: TextStyle(fontSize: 16,color: Colors.white,fontWeight: FontWeight.bold),),
                                  ],
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          decoration:const BoxDecoration(
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(20),bottomLeft: Radius.circular(20)),
                            color: Color(0xff379777)
                          ),
                          width: 100,
                          height: 40,
                          child:const Center(
                            child: Text('0-100',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold,color: Colors.white),),
                          ),
                        ),
                        Container(
                          decoration:const BoxDecoration(
                            color: Color(0xffF4CE14)
                          ),
                          width: 100,
                          height: 40,
                          child:const Center(
                            child: Text('100-200',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold,color: Colors.white),),
                          ),
                        ),
                        Container(
                          decoration:const BoxDecoration(
                            borderRadius: BorderRadius.only(topRight: Radius.circular(20),bottomRight: Radius.circular(20)),
                            color: Color(0xffDC143C)
                          ),
                          width: 100,
                          height: 40,
                          child:const Center(
                            child: Text('200+',style: TextStyle(fontSize: 16,fontWeight: FontWeight.bold,color: Colors.white),),
                          ),
                        ),
                        const SizedBox(width: 20,),
                        IconButton(onPressed: ()=>{showSettings()}, icon: Icon(Icons.settings, color: Colors.white,size: 40,)),
                        const SizedBox(width: 10,)
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}