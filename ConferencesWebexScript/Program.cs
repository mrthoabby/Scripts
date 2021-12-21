using ConferencesWebexScript.ApiTemplates;
using ConferencesWebexScript.Entities;
using ConferencesWebexScript.Helpers;
using ConferencesWebexScript.Services;
using System;

namespace ConferencesWebexScript
{
    internal class Program
    {
        static void Main(string[] args)
        {
            //Se le adiciona 1 minuto a la tarea para que no se pisen las mangueras
            var CurrentTime = DateTime.Now.AddMinutes(1);

            var conferencingParameters = ScriptConfigurationHelper.GetConferenceParameter();

            if (conferencingParameters is null) throw new Exception("No se han configurado de manera correcta los parametros para iniciar la conferencia");

            conferencingParameters.Start_time = CurrentTime.ToString("s");
            conferencingParameters.End_time = CurrentTime.AddHours(12).ToString("s");

            var _conference = Conference.CreateConferenceAsync(new ConferenceRequestCreate() { Data_create_update = conferencingParameters }).Result;
            if (_conference.IsConferenceCreate) Console.WriteLine(_conference.ConferenceContent.title);
            Console.ReadKey();
        }
    }
}
