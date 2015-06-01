package de.qlearning

import java.awt.EventQueue
import scala.collection.immutable.Stack
import akka.actor.Actor
import org.nlogo.app.App
import org.nlogo.agent.ArrayAgentSet
import org.nlogo.workspace.AbstractWorkspace
import org.nlogo.api.SimpleJobOwner
import org.nlogo.api.Observer
import org.nlogo.api.Agent
import org.nlogo.api.DefaultReporter
import org.nlogo.nvm.Procedure
import akka.dispatch.Future

import akka.dispatch.ExecutionContext
import akka.actor.ActorRef

object NetLogoActors {
  
  case class Init(commandName: String)
  case object UpdateGUI
  case object ReturnData
  case class AlteredAgent(agent: Agent, alt: String, reward: Double)
  
}

class NetLogoGUIActor(nlApp: App, rewardReporterName: String, helper: RewardProcedureHelper) extends Actor {
  import NetLogoActors._
  import QLSystem._
  
  val reporter = nlApp.workspace.compileReporter(rewardReporterName + " 1")
 
  def receive = {
    case QLAgent.Choice(agent, alternative) => {
      helper.setParameter(1, agent, alternative)
      val result = nlApp.workspace.runCompiledReporter(nlApp.owner, reporter).asInstanceOf[Double]
      sender ! QLAgent.Reward(result)
    }
  }
  
//  implicit val ec = QLSystem.system
//  
//  def needsGUIUpdateCommand: Receive = {
//    case Init(commandName) =>
//      context.become(collectingData(nlApp.workspace.compileCommands(commandName), List[(Agent,String,Double)](), List[(Agent,String,Double)]()))
//  }
//  
//  def collectingData(command: Procedure, data: List[(Agent,String,Double)], alteredData: List[(Agent,String,Double)]): Receive = {
//    case newEntry: AlteredAgent =>
//      context.become(collectingData(command, (newEntry.agent, newEntry.alt, newEntry.reward) :: data, alteredData))
//      
//    case Init(commandName) =>
//      context.become(collectingData(nlApp.workspace.compileCommands(commandName), List[(Agent,String,Double)](), List[(Agent,String,Double)]()))
//      
//    case UpdateGUI =>
//      println("begin: update gui")
//      val future = Future {
//        nlApp.workspace.runCompiledCommands(nlApp.owner, command)
//      }
//      println("data: " + data.length + " items")
//      context.become(collectingData(command, List[(Agent,String,Double)](), data))
//      println("end: update gui")
//      
//    case ReturnData =>
//      println("return data: " + alteredData.size + " items")
//      sender ! alteredData
//  }
  
}

class NetLogoHeadlessActor(id: Int, modelPath: String, rewardReporterName: String, helper: RewardProcedureHelper) extends Actor {
  import NetLogoActors._
  import QLSystem._
  
  import org.nlogo.headless.HeadlessWorkspace
  val workspace = HeadlessWorkspace.newInstance
  workspace.open(modelPath)
  val reporter = workspace.compileReporter(rewardReporterName + " " + id)
  
  override def postStop(): Unit = {
    workspace.dispose()
  }
  
  def receive = {
    case QLAgent.Choice(agent, alternative) => {
      helper.setParameter(id, agent, alternative)
//      println(finished)
      val result = workspace.runCompiledReporter(workspace.defaultOwner, reporter).asInstanceOf[Double]
//      if (result.first.asInstanceOf[Agent] != agent) println("not the same agent")
//      if (result.tail.first.asInstanceOf[String] != alternative) println("not the same alternative")
//      println( result.first.asInstanceOf[Agent].toString() + " " +  agent.toString())
//      println( result.tail.first.asInstanceOf[String].toString() + " " + alternative)
//      println(agent + " " + alternative + " " + result)
//      nlguiActor ! AlteredAgent(agent, alternative, result)
      sender ! QLAgent.Reward(result)
    }
  }
  
}