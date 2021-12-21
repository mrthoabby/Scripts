using ConferencesWebexScript.Helpers;

namespace ConferencesWebexScript.Interfaces
{
    internal interface ICredentials
    {
        public string Event{get;set;}
        public string AuToken
        {
            get { return ScriptConfigurationHelper._auToken;}
        }
        public string IntegrationId
        {
            get { return ScriptConfigurationHelper._integrationId; }
        }
    }
}
