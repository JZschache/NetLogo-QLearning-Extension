package de.qlearning

//import scala.compat.Platform
import akka.actor.{Actor, ActorRef, FSM}
import akka.agent.{Agent => AkkaAgent}
import akka.dispatch.Future
import akka.pattern.ask
import akka.util.duration._
import akka.util.Timeout
import de.qlearning.util.RandomHelper
import akka.actor.Cancellable
//import akka.util.Timeout


object QLAgent {

  // finding an object with the highest value
  sealed trait HasValue { val value : Double}
  def maximum[A <: HasValue](list: Iterable[A]) = {
    require(list.size >= 1)
    list.tail.foldLeft(List(list.head))((result,b) => 
      scala.math.signum(result.head.value - b.value) match {
        case -1 => List(b)
        case 1 => result
        case 0 => b :: result
      })
  }
  
  // the QValue-Object
  class QValue(val alt: String, val n: Double, val value: Double) extends HasValue {
    
    def updated(amount: Double) : QValue = {
      val newValue = value + (1.0 /(n + 1.0)) * (amount - value)
      new QValue(alt, n + 1.0, newValue)
    }
  }
  
  // an object holding all the data of interest
  class QLData(val qValuesMap: Map[String,QValue], val nMap: Map[String, Double], val nTotal: Double, val lastChoice: String) {
    
//    def ++(newAlternatives: List[String]) = {
//      val newQvalue = qValuesMap ++ newAlternatives.map(alt => (alt -> new QValue(alt, 0.0, 0.0)))
//      val newN = nMap ++ newAlternatives.map(_ -> 0.0)
//      new QLData(newQvalue, newN, nTotal, lastChoice)
//    }
    
    def updated(alt:String, reward: Double) : QLData = {
      val newQvalue = qValuesMap.getOrElse(alt, new QValue(alt, 0.0, 0.0)).updated(reward)
      val newN = nMap.getOrElse(alt, 0.0) + 1.0
      new QLData(qValuesMap.updated(alt, newQvalue), nMap.updated(alt, newN), nTotal + 1, alt)
    }
    
    def this() = this(Map[String,QValue](), Map[String, Double](), 0.0, "")
    
//    def this(newAlternatives: List[String]) = this(newAlternatives.map(alt => (alt -> new QValue(alt, 0.0, 0.0))).toMap,
//        newAlternatives.map(_ -> 0.0).toMap, 0.0, "")
    
  }
  
  // various decision making algorithms
  def getDecisionAlgorithm(exploration: String, dataAgent: AkkaAgent[QLAgent.QLData]) = {
    exploration match {
      case "epsilon-greedy" => epsGreedy(dataAgent, _:List[String], _:Double, _:RandomHelper)
      case "softmax" => softmax(dataAgent, _:List[String], _:Double, _:RandomHelper)
    }
  }
  private def epsGreedy(dataAgent: AkkaAgent[QLAgent.QLData], alternatives: List[String], epsilon: Double, rh: RandomHelper): String = {
      if (rh.uniform.nextDoubleFromTo(0, 1) < epsilon)
        rh.randomComponent(alternatives)
      else {
        val qvm = dataAgent.get.qValuesMap
        val maxima = maximum(alternatives.map(alt => qvm.getOrElse(alt, new QValue(alt, 0.0, 0.0))))
        if (maxima.length == 1) maxima.head.alt  else rh.randomComponent(maxima).alt
      }
    }
    
  private def softmax(dataAgent: AkkaAgent[QLAgent.QLData], alternatives: List[String], temperature:Double, rh: RandomHelper): String = {
      val qvm = dataAgent.get.qValuesMap
      val qvalues = alternatives.map(alt => qvm.getOrElse(alt, new QValue(alt, 0.0, 0.0)))
      val expForm = qvalues.scanLeft(("".asInstanceOf[String], 0.0))((temp, qva) => (qva.alt, temp._2 + scala.math.exp(qva.value / temperature))).tail
      val randomValue = rh.uniform.nextDoubleFromTo(0, expForm.last._2)
      expForm.find(randomValue < _._2).get._1    
    }
  
  // a class that holds data and helps with the decision making
  class Decisions(val experimenting: Double, val decisionAlg: (List[String], Double, RandomHelper) => String, var decrease: Boolean = false, var n: Double = 0.0) {

    def next(alternatives: List[String], rh:RandomHelper) = {
      if (decrease){
        n += 1.0
        decisionAlg(alternatives, experimenting / n, rh)
      } else
        decisionAlg(alternatives, experimenting, rh)
    }
    
    def startDecreasing = {
      decrease = true
    }
    
  }

  // messages QLAgent
  case object DecExp
  case class Choose(alternatives: List[String], rh: RandomHelper)
  case class Choice(alternative: String)
  case class Reward(alternative: String, amount: Double)

  // states GroupActor
  sealed class State
  case object Idle extends State
  case object Active extends State
  // data GroupActor
  sealed class Data
  case object NoGroup extends Data
  case class WithGroup(nlGroup: NLGroup, scheduler: Cancellable) extends Data
  //messages GroupActor
  case class SetGroup(nlGroup: NLGroup)
  case class Start(once: Boolean, pauseMS: Int)
  case object Stop
    
}


class GroupActor(router: ActorRef, seed:Int) extends Actor with FSM[QLAgent.State, QLAgent.Data]{
  import QLAgent._
  
  val rh = new util.RandomHelper(seed)
  implicit val ec = context.dispatcher
  
  //private messages
  case object Tick
  
  startWith(Idle, NoGroup)
  
  when(Idle) {
    case Event(SetGroup(nlGroup), _) =>
      stay using WithGroup(nlGroup, null)
    
    case Event(Start(once, pauseMS), WithGroup(nlGroup,_)) =>
      if (once) {
        val scheduler = context.system.scheduler.scheduleOnce(pauseMS.milliseconds, self, Tick)
        goto(Active) using WithGroup(nlGroup, scheduler)
      } else { 
        context.system.scheduler.schedule(pauseMS.milliseconds, pauseMS.milliseconds, self, Tick)
        stay
      }
  }
  when(Active) {
    case Event(Stop, WithGroup(nlGroup, scheduler)) => 
      scheduler.cancel
      goto(Idle)
  }
  
  whenUnhandled {
    case Event(Tick, WithGroup(nlGroup, scheduler)) =>
      implicit val timeout = Timeout(60 seconds)
      Future.sequence(nlGroup.group.map(triple => {
        val ar = triple._2
        val future = (ar ? QLAgent.Choose(triple._3, rh)).mapTo[QLAgent.Choice]
        future.map(f => (triple._1, ar, f))
      })) onSuccess {
        case result =>
          val unzipped = result.unzip3
          router ! NetLogoActors.GroupChoice(unzipped._1, unzipped._2, unzipped._3.map(_.alternative))
      }
      stay
    case Event(Start, _) =>
      goto(Idle)
    case Event(Stop, _) =>
      goto(Idle)
  }
      
  initialize
  
}

class QLAgent(val dataAgent: AkkaAgent[QLAgent.QLData], val experimenting: Double, val exploration: String) extends Actor {
  import QLSystem._
  import QLAgent._
  
  
//  val generator: RandomEngine  = new MersenneTwister64(Platform.currentTime.toInt)
//  val uniform = new Uniform(generator)
  
  private var decisions = new Decisions(experimenting, getDecisionAlgorithm(exploration, dataAgent))
  
//  startWith(Idle, Uninitialized)
  
//  when(Idle) {
//    case Event(Init(experimenting, exploration), _) =>
//      dataAgent update new QLData()
//      stay using Initialized(new Decision(experimenting, exploration))
      
  def receive = {
//    case AddChoiceAltList(altList, replace) =>
//      if (replace)
//        dataAgent update new QLData(altList)
//      else
//        dataAgent send { _ ++ altList }
      
//    case Event(AddGroup(newGroup: ActorRef), Initialized(groups, lastChoices, choice)) =>
//      
//      stay using Initialized(newGroup :: groups, lastChoices, choice)
//      
      
//    case Event(Start, data: Initialized) =>
//      goto(Choosing)
//  }
  
//  onTransition {
//    case _ -> Choosing =>
//      context.system.scheduler.scheduleOnce(QLSystem.pbc.milliseconds, self, Choose)
//  }
  
//  when(Choosing){
    
    case Choose(altList, rh) => 
      sender ! Choice(decisions.next(altList, rh))
//      val decisions = if (groups.isEmpty){
//        val c = choice.next
//        environment ! Choice(c)
//        List[String](c)
//      } else {
//        // TODO: what to do if member of multiple groups
//        val c = choice.next
//        groups.first ! Choice(c)
//        List[String](c)
//      }
//      goto(Waiting) using Initialized(choice.update)
      
    case Reward(alt, amount) =>
      dataAgent send { _.updated(alt, amount) }
      
    case DecExp => 
      decisions.startDecreasing
  }
  
//  when(Waiting){
//    case Event(Reward(alt, amount), _) =>
//      dataAgent send { _.updated(alt, amount) }
//      //TODO: what to do if member of multiple groups
//      goto(Choosing)
//  }
  
//  whenUnhandled {
//    case Event(Stop, _) =>
//      goto(Idle)
//    case Event(Reward(_, _), _) =>
//      stay
//    case Event(Choose,_) =>
//      stay
//    case Event(DecExp, Initialized(choice)) =>
//      stay using Initialized(choice.startDecreasing)
//  }
//    
//  initialize
}