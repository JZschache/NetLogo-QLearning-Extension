package de.qlearning

import java.util.concurrent.atomic.AtomicInteger
import scala.collection.immutable.Queue
import akka.actor.{Actor,ActorRef,FSM,SupervisorStrategy,Props}
import akka.agent.{Agent => AkkaAgent}
import akka.routing.{Broadcast,Route,RouteeProvider,RouterConfig,Destination}
import akka.dispatch.{Future,Dispatchers}
import akka.util.duration._
import de.util.PerformanceMeasure
import org.nlogo.app.ModelSaver
import de.qlextension.QLExtension


object NetLogoHeadlessActor {
  
  // states
  sealed trait State
  case object NotReady extends State
  case object Ready extends State
  case object Waiting extends State
  // data
  sealed trait Data
  case object Uninitialized extends Data
  case class Initialized(reporter: org.nlogo.nvm.Procedure, data: List[NLGroupChoice]) extends Data
  //messages
  case class OpenModel(path:String, settings: List[(String, Any)])
  case class NLGroupChoicesList(list: List[NLGroupChoice])
  case class GetNLGroupChoices(id: Int)
  case class IAmReady(headlessId: Int)
}

/**
 * the NetLogoHeadlessActor needs an id to share data
 * with an instance of the NetLogoHeadlessWorkspace (via the extension).
 * 
 * This kind of sharing data has better performance than setting the parameters 
 * directly and recompiling the reward-reporter 
 * (see also: https://groups.google.com/forum/#!msg/netlogo-devel/8oDmCRERDlQ/0IDZm015eNwJ). 
 */

class NetLogoHeadlessActor(val id: Int) extends Actor with FSM[NetLogoHeadlessActor.State, NetLogoHeadlessActor.Data]{
  import NetLogoHeadlessActor._
  import QLSystem._
  import org.nlogo.headless.HeadlessWorkspace

//  val workspace = HeadlessWorkspace.newInstance(classOf[MyHeadlessWorkspace])
  val workspace = HeadlessWorkspace.newInstance
  val rewardRepName = config.getString(QLExtension.cfgstr + ".parallel.reward-reporter-name")
//  val setupComName = config.getString(QLExtension.cfgstr + ".setup-command-name")
  
  override def postStop() {
    workspace.dispose()
  }
  
  private def openModel(path:String, settings: List[(String, Any)]) {
    workspace.modelOpened = false
    workspace.open(path)
    for((name, value) <- settings) {
      if(workspace.world.observerOwnsIndexOf(name.toUpperCase) == -1)
        throw new org.nlogo.api.ExtensionException("Global variable does not exist:\n" + name)
      workspace.world.setObserverVariableByName(name, value)
    }
    netLogoSuper ! IAmReady(id)
  }
  
  startWith(NotReady, Uninitialized)
  
  when(NotReady) {
   
    case Event(OpenModel(path, settings), _) => {
      openModel(path, settings)
      goto(Ready) using Initialized(workspace.compileReporter(rewardRepName + " " + id), null)
    }
  }
  
  // ready to handle requests (list of NLGroups)
  when(Ready) {
    
    // can only be received in state Ready
    case Event(NetLogoSupervisor.NLGroupsList(_, groups), _) => {
      
//      println(id + ": groups: " + groups)
      
      val time1 = scala.compat.Platform.currentTime
      QLSystem.perfMeasures.stopHeadlessIdlePerf(id, time1)
      QLSystem.perfMeasures.startHeadlessHandleGroupsPerf(id, time1)
      
      Future.sequence(groups.map(group => Future.sequence((group.qlAgents zip group.alternatives).map(pair => 
        pair._1.future map {_.choose(pair._2)}
      )))) onComplete {
        case Right(list) =>  {
//          println(id + ": success: " + list)
          // forward choices of agents to self
          val groupsChoices = (groups zip list).map(pair => NLGroupChoice(pair._1.nlAgents, pair._1.qlAgents, pair._2, Nil, Nil))
//          println(id + ": groupsChoices: " + groupsChoices)
          self ! NLGroupChoicesList(groupsChoices)
        }
        case Left(failure) =>
          failure.printStackTrace()
      }
      
      val time2 = scala.compat.Platform.currentTime
      QLSystem.perfMeasures.stopHeadlessHandleGroupsPerf(id, time2)
      QLSystem.perfMeasures.startHeadlessIdlePerf(id, time2)
      
      goto(Waiting)
    }

  }
  
  /**
   * first, the actor waits for the choices of the agents (NLGroupChoicesList(groupsChoices))
   * then, the actor waits for the NLHeadlessWorkspace to ask for this data
   * 
   * afterwards, he is ready to receive new requests from NetLogoSupervisor
   */
  when(Waiting) {
    
    case Event(NLGroupChoicesList(list), Initialized(reporter, _)) => {
      
//      println(id + ": list: " + list)
      
      val time1 = scala.compat.Platform.currentTime
      QLSystem.perfMeasures.stopHeadlessIdlePerf(id, time1)
      QLSystem.perfMeasures.startHeadlessHandleChoicesPerf(id, time1)
            
      Future {
          workspace.runCompiledReporter(workspace.defaultOwner, reporter).asInstanceOf[org.nlogo.api.LogoList]
      } onComplete {
        case Right(result) =>
          result.foreach(ar => {
            // forwards rewards to agents
            val groupChoice = ar.asInstanceOf[NLGroupChoice]
            val ars = (groupChoice.choices, groupChoice.rewards, groupChoice.newStates).zipped.map((a,r,s) => (a,r,s))
            (groupChoice.qlAgents, ars).zipped.foreach((agent, ars) => agent send {_.updated(ars._1, ars._2, ars._3) }) 
          })
        case Left(failure) => failure.printStackTrace()
      }
      
      val time2 = scala.compat.Platform.currentTime
      QLSystem.perfMeasures.stopHeadlessHandleChoicesPerf(id, time2)
      QLSystem.perfMeasures.startHeadlessIdlePerf(id, time2)
      
      stay using Initialized(reporter, list)
    }
    
    case Event(GetNLGroupChoices(_), Initialized(_, data)) => {
      
      QLSystem.perfMeasures.stopHeadlessIdlePerf(id, scala.compat.Platform.currentTime)
      
      sender ! 	NLGroupChoicesList(data)
      
      QLSystem.perfMeasures.startHeadlessIdlePerf(id, scala.compat.Platform.currentTime)
      
      netLogoSuper ! IAmReady(id)
      goto(Ready)
    }
    
  }
  
  whenUnhandled {
    // can be received in any state (especially when NotReady)
    case Event(OpenModel(path, settings), _) => {
      openModel(path, settings)
      goto(Ready) using Initialized(workspace.compileReporter(rewardRepName + " " + id), null)
    }
    
    case Event(NLGroupChoicesList(_), _) => // ignore (e.g. after opening a new model)
      stay
      
    case Event(GetNLGroupChoices(_), _) => // ignore (e.g. after opening a new model)
      stay
    
  }
  
  initialize

}

/**
 * A custom router that is similar to RoundRobin but also forwards messages with id
 * (GetNLGroupChoices(id)) to a particular NLHeadlessActor
 * 
 */
case class NetLogoHeadlessRouter(size: Int) extends RouterConfig {
 
  def routerDispatcher: String = Dispatchers.DefaultDispatcherId
//  def routerDispatcher: String = "pinned-dispatcher"
  def supervisorStrategy: SupervisorStrategy = SupervisorStrategy.defaultStrategy
 
  def createRoute(routeeProps: Props, routeeProvider: RouteeProvider): Route = {
    
    val currentRoutees = if (size < 1) 
      IndexedSeq(routeeProvider.context.system.deadLetters)
    else
      (0 until size).map(id => {
//        routeeProvider.context.actorOf(Props(new NetLogoHeadlessActor(id)).withDispatcher("pinned-dispatcher"))
        routeeProvider.context.actorOf(Props(new NetLogoHeadlessActor(id)))
      }).toIndexedSeq
 
    routeeProvider.registerRoutees(currentRoutees)
    
//    val next = new AtomicInteger(0)
//
//    def getNext(): ActorRef = { if (size <= 1)
//        currentRoutees(0)
//      else {
//        val nextId = next.get
//        next.set((nextId + 1) % size)
//        currentRoutees(nextId)
//      }
//    }

    
    {
      case (sender, message) =>
        message match {
          case NetLogoHeadlessActor.GetNLGroupChoices(id) => List(Destination(sender, currentRoutees(id)))
          case NetLogoSupervisor.NLGroupsList(id, _) => List(Destination(sender, currentRoutees(id)))
          case Broadcast(msg) => toAll(sender, currentRoutees)
//          case msg => List(Destination(sender, getNext()))
        }
    }

}
 
}